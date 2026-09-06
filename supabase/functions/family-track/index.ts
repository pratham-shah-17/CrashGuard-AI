/**
 * Family tracking viewer: GET ?t=<token> returns HTML or JSON (Accept header).
 * Uses service role to read one row — no direct anon table exposure.
 *
 * Deploy: supabase functions deploy family-track --no-verify-jwt
 * (--no-verify-jwt so browser opens link without Authorization header.)
 *
 * Env (automatic on hosted Supabase): SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
 */
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const allowOrigin = Deno.env.get("FAMILY_TRACK_ALLOWED_ORIGIN") ?? "";
const cors = {
  // Default is same-origin only; set FAMILY_TRACK_ALLOWED_ORIGIN="*" explicitly for demos.
  ...(allowOrigin.trim() && allowOrigin.trim() !== "null" ? { "Access-Control-Allow-Origin": allowOrigin.trim() } : {}),
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, accept",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
};

function htmlPage(row: Record<string, unknown>): string {
  const lat = Number(row["latitude"]);
  const lng = Number(row["longitude"]);
  const summary = String(row["triage_summary"] ?? "").slice(0, 800);
  const sev = row["severity"] != null ? String(row["severity"]) : "—";
  const template =
    Deno.env.get("MAPS_LINK_TEMPLATE") ??
    "https://www.google.com/maps?q={lat},{lng}";
  const maps = !Number.isFinite(lat) || !Number.isFinite(lng)
    ? "#"
    : template.replaceAll("{lat}", String(lat)).replaceAll("{lng}", String(lng));
  const safeSummary = summary
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <meta http-equiv="refresh" content="10"/>
  <meta name="referrer" content="no-referrer"/>
  <title>RoadSOS · Live location</title>
  <style>
    body { font-family: system-ui, sans-serif; background:#080A0D; color:#fff; margin:0; padding:24px; max-width:560px; }
    h1 { font-weight:700; font-size:1.25rem; letter-spacing:.04em; color:#E8281A; }
    .mono { font-family: ui-monospace, monospace; font-size:0.9rem; color:#00B8A0; }
    a { color:#00B8A0; }
    .card { border:1px solid rgba(255,255,255,.07); padding:16px; margin-top:16px; }
  </style>
</head>
<body>
  <h1>ROADSOS · TRACKING</h1>
  <p class="mono">Severity: ${sev}</p>
  <p class="mono">Lat ${Number.isFinite(lat) ? lat.toFixed(3) : "—"} · Lng ${Number.isFinite(lng) ? lng.toFixed(3) : "—"}</p>
  <p><a href="${maps}" rel="noopener">Open location</a></p>
  <div class="card"><p>${safeSummary || "Triage summary updating…"}</p></div>
  <p style="opacity:.7;font-size:.85rem;margin-top:24px">Page auto-refreshes every 10s. Link expires per incident policy.</p>
</body>
</html>`;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: cors });
  }
  if (req.method !== "GET") {
    return new Response(JSON.stringify({ error: "method_not_allowed" }), {
      status: 405,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  const url = new URL(req.url);
  const token = url.searchParams.get("t")?.trim();
  if (!token) {
    return new Response(JSON.stringify({ error: "missing_token" }), {
      status: 400,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }
  // Basic input hardening (prevents weird logs / accidental massive tokens).
  if (token.length > 128) {
    return new Response(JSON.stringify({ error: "invalid_token" }), {
      status: 400,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) {
    return new Response(JSON.stringify({ error: "server_misconfigured" }), {
      status: 500,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  const supabase = createClient(supabaseUrl, serviceKey);
  const { data, error } = await supabase
    .from("incident_live_links")
    .select(
      "latitude, longitude, accuracy_m, triage_summary, severity, expires_at, incident_id, updated_at",
    )
    .eq("token", token)
    .maybeSingle();

  if (error) {
    return new Response(JSON.stringify({ error: "lookup_failed" }), {
      status: 500,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }
  if (!data) {
    return new Response(JSON.stringify({ error: "not_found" }), {
      status: 404,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  const exp = data["expires_at"] as string | null;
  if (exp && new Date(exp).getTime() < Date.now()) {
    return new Response(JSON.stringify({ error: "expired" }), {
      status: 410,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  const accept = req.headers.get("accept") ?? "";
  if (accept.includes("application/json")) {
    return new Response(
      JSON.stringify({
        incident_id: data["incident_id"],
        // Minimize by default: coarse location is enough for family pickup decisions.
        latitude: typeof data["latitude"] === "number"
          ? Number((data["latitude"] as number).toFixed(3))
          : data["latitude"],
        longitude: typeof data["longitude"] === "number"
          ? Number((data["longitude"] as number).toFixed(3))
          : data["longitude"],
        accuracy_m: data["accuracy_m"],
        severity: data["severity"],
        triage_summary: data["triage_summary"],
        updated_at: data["updated_at"],
        expires_at: data["expires_at"],
      }),
      {
        headers: {
          ...cors,
          "Content-Type": "application/json; charset=utf-8",
          "Cache-Control": "no-store",
          "Referrer-Policy": "no-referrer",
        },
      },
    );
  }

  return new Response(htmlPage(data as Record<string, unknown>), {
    headers: {
      ...cors,
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "no-store",
      "Referrer-Policy": "no-referrer",
    },
  });
});
