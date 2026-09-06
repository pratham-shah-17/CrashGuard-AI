/**
 * Scheduled Edge Function: query Overpass **once per job** (server-side), upsert into Postgres.
 *
 * Clients must never call Overpass directly at app scale — use PowerSync for reads.
 *
 * Schedule: Supabase Dashboard → Edge Functions → cron / pg_net, or external cron POST to:
 *   POST /functions/v1/sync-osm-facilities  (requires Authorization: Bearer <service_role or anon per your policy>)
 *
 * Env (set in Supabase project secrets):
 *   SYNC_BBOX — optional JSON { south, west, north, east }. Default: rough India bbox.
 *   OVERPASS_URL — optional. Default https://overpass-api.de/api/interpreter
 */
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import * as crypto from "node:crypto";

type BBox = { south: number; west: number; north: number; east: number };

const defaultBBox: BBox = {
  south: 8.0,
  west: 68.0,
  north: 37.5,
  east: 97.5,
};

function parseBBox(): BBox {
  const raw = Deno.env.get("SYNC_BBOX");
  if (!raw) return defaultBBox;
  try {
    const j = JSON.parse(raw) as BBox;
    if (
      typeof j.south === "number" &&
      typeof j.west === "number" &&
      typeof j.north === "number" &&
      typeof j.east === "number"
    ) {
      return j;
    }
  } catch (_) {
    /* fall through */
  }
  return defaultBBox;
}

function mapElement(el: Record<string, unknown>): Record<string, unknown> | null {
  const tags = el["tags"] as Record<string, string> | undefined;
  if (!tags) return null;

  const id = String(el["id"]);
  const name =
    tags["name"] ?? tags["operator"] ?? "Emergency Facility";

  let type = "emergency";
  if (tags["amenity"]) type = tags["amenity"];
  else if (tags["shop"] === "car_repair") type = "puncture_shop";
  else if (tags["shop"] === "car") type = "showroom";

  let lat = el["lat"] as number | undefined;
  let lon = el["lon"] as number | undefined;
  const center = el["center"] as Record<string, number> | undefined;
  if ((lat === undefined || lat === 0) && center) {
    lat = center["lat"];
    lon = center["lon"];
  }
  if (lat === undefined || lon === undefined || lat === 0) return null;

  const phone = tags["phone"] ?? tags["contact:phone"] ?? null;

  return {
    id,
    name,
    type,
    latitude: lat,
    longitude: lon,
    contact_number: phone,
    capabilities: null,
    data_source: "osm",
    state_code: null,
    district: null,
    updated_at: new Date().toISOString(),
  };
}

Deno.serve(async (req: Request) => {
  // Hard gate: require an explicit trigger token to avoid accidental public invocation.
  // Configure `SYNC_TRIGGER_TOKEN` as an Edge Function secret.
  const trigger = Deno.env.get("SYNC_TRIGGER_TOKEN")?.trim() ?? "";
  if (trigger) {
    const auth = req.headers.get("authorization") ?? "";
    const expected = `Bearer ${trigger}`;

    const encoder = new TextEncoder();
    const a = encoder.encode(auth);
    const b = encoder.encode(expected);

    if (a.byteLength !== b.byteLength || !crypto.timingSafeEqual(a, b)) {
      return new Response(JSON.stringify({ error: "unauthorized" }), {
        status: 401,
        headers: { "Content-Type": "application/json; charset=utf-8" },
      });
    }
  }

  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) {
    return new Response(
      JSON.stringify({ error: "Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY" }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }

  const bbox = parseBBox();
  const { south, west, north, east } = bbox;

  // Mirrors legacy client query shape; runs server-side only.
  const query = `
    [out:json][timeout:120];
    (
      node["amenity"~"hospital|police|fire_station|ambulance"](${south},${west},${north},${east});
      way["amenity"~"hospital|police|fire_station|ambulance"](${south},${west},${north},${east});
      node["shop"~"car_repair|car"](${south},${west},${north},${east});
    );
    out body;
    >;
    out skel qt;
  `.trim();

  const overpass =
    Deno.env.get("OVERPASS_URL") ?? "https://overpass-api.de/api/interpreter";

  let osmJson: { elements?: Record<string, unknown>[] };
  try {
    const res = await fetch(overpass, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: `data=${encodeURIComponent(query)}`,
    });
    if (!res.ok) {
      const t = await res.text();
      console.error(`Overpass HTTP error ${res.status}:`, t);
      return new Response(
        JSON.stringify({ error: "Overpass HTTP error", status: res.status }),
        { status: 502, headers: { "Content-Type": "application/json" } },
      );
    }
    osmJson = await res.json();
  } catch (e) {
    console.error("Overpass fetch failed:", e);
    return new Response(
      JSON.stringify({ error: "Overpass fetch failed" }),
      { status: 502, headers: { "Content-Type": "application/json" } },
    );
  }

  const elements = osmJson.elements ?? [];
  const rows: Record<string, unknown>[] = [];
  for (const el of elements) {
    const row = mapElement(el as Record<string, unknown>);
    if (row) rows.push(row);
  }

  const supabase = createClient(url, key);

  const chunk = 400;
  let upserted = 0;
  for (let i = 0; i < rows.length; i += chunk) {
    const part = rows.slice(i, i + chunk);
    const { error } = await supabase
      .from("emergency_facilities")
      .upsert(part, { onConflict: "id" });
    if (error) {
      return new Response(JSON.stringify({ error: error.message, at: i }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      });
    }
    upserted += part.length;
  }

  return new Response(
    JSON.stringify({
      ok: true,
      bbox,
      elements: elements.length,
      upserted,
    }),
    { headers: { "Content-Type": "application/json" } },
  );
});
