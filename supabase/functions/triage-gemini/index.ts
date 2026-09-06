/**
 * Supabase Edge Function: triage-gemini
 *
 * Server-side Gemma 4 27B triage so mobile clients never hold API keys.
 * Model: gemma-4-27b-it (multimodal — supports both text and image input)
 * Fallback: gemma-3-27b-it (text-only)
 *
 * Gemma 4 vision: if the client sends a crash-scene photo (base64 JPEG),
 * Gemma 4 analyzes it for: fire, smoke, trapped persons, vehicle count,
 * fluid spills, road type, damage extent. This dramatically improves
 * severity classification vs. text-only description.
 *
 * Requires Supabase secret:
 * - GEMMA_API_KEY  (Google AI Studio key — same endpoint as Gemini)
 *
 * Flutter invocation:
 *   Supabase.instance.client.functions.invoke('triage-gemini', body: {
 *     'transcript': '...',
 *     'location': 'lat,lng',
 *     'severity_hint': 4,
 *     'language_code': 'en',
 *     'image_base64': '<optional base64 JPEG>',  // Gemma 4 vision
 *     'image_type': 'image/jpeg',
 *   })
 */
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const GEMMA_4_MODEL = "gemma-4-27b-it";
const GEMMA_3_FALLBACK = "gemma-3-27b-it"; // text-only — no image parts

type ReqBody = {
  schema?: string;
  transcript?: string;
  location?: string;
  severity_hint?: number;
  language_code?: string;
  image_base64?: string;   // optional crash-scene photo — Gemma 4 vision
  image_type?: string;     // MIME type, default "image/jpeg"
};

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8" },
  });
}

/** Whole JSON body limit (~3 MB text) — abuse / OOM protection */
const MAX_BODY_CHARS = 3_000_000;
/** Vision payload limit (base64 JPEG); reject before upstream API */
const MAX_IMAGE_BASE64_CHARS = 2_600_000;

/** Truncate error text returned to clients — never leak full vendor payloads */
function safeDetail(err: unknown, max = 280): string {
  const s = String(err);
  return s.length <= max ? s : `${s.slice(0, max)}…`;
}

function buildTextPrompt(input: {
  transcript: string;
  location: string;
  severityHint: number;
  languageCode: string;
  hasImage: boolean;
}): string {
  const langHint =
    input.languageCode === "en"
      ? "User may write in English or Indian languages (Hindi, Tamil, Bengali, Marathi, Telugu)."
      : `User text may be in Hindi or mixed English-${input.languageCode}. JSON field values must be in English.`;

  const visionNote = input.hasImage
    ? "A crash-scene photo has been provided. Analyze it for: fire or smoke visible, vehicle count, persons visible and whether trapped or mobile, fluid spills, road surface (highway/urban/rural), collision type (rear-end, rollover, head-on). Incorporate visual findings into thinking_summary and severity_level."
    : "";

  return `You are an emergency triage AI for RoadSOS (India road accident platform).
Analyze the situation and respond with ONLY valid JSON (no markdown, no text before or after):
{
  "severity_level": <int 1-5, where 5=life-threatening/critical, 4=critical, 3=serious, 2=moderate, 1=minor>,
  "required_services": <array from: ambulance, police, fire_department, rescue, towing, puncture_shop, showroom>,
  "first_aid_focus": <single most urgent first aid action, English, one sentence>,
  "thinking_summary": <one sentence explaining severity reasoning and key clinical/scene factors, English>
}
Rules:
- When uncertain about severity, ALWAYS bias higher — a false positive costs money; a false negative costs lives.
- Always include "ambulance" unless it is purely a mechanical breakdown with zero injury.
- GPS: ${input.location} | Crash sensor severity hint: ${input.severityHint}/5
- ${langHint}
${visionNote}
Emergency transcript: "${input.transcript}"`;
}

function extractModelText(decoded: Record<string, unknown>): string {
  const candidates = decoded["candidates"];
  if (!Array.isArray(candidates) || candidates.length === 0) return "";
  const first = candidates[0] as Record<string, unknown>;
  const content = first?.["content"] as Record<string, unknown> | undefined;
  const parts = content?.["parts"] as unknown[] | undefined;
  if (!Array.isArray(parts)) return "";
  let out = "";
  for (const p of parts) {
    if (p && typeof p === "object" && typeof (p as Record<string, unknown>)["text"] === "string") {
      out += String((p as Record<string, unknown>)["text"]);
    }
  }
  return out;
}

function extractFirstJsonObject(raw: string): Record<string, unknown> {
  let text = (raw ?? "").trim();
  if (!text) throw new Error("empty_model_output");

  if (text.startsWith("```")) {
    const firstNl = text.indexOf("\n");
    if (firstNl >= 0) text = text.substring(firstNl + 1);
    const fenceEnd = text.lastIndexOf("```");
    if (fenceEnd >= 0) text = text.substring(0, fenceEnd);
    text = text.trim();
  }

  const start = text.indexOf("{");
  const end = text.lastIndexOf("}");
  if (start < 0 || end <= start) throw new Error("no_json_object");
  const snippet = text.substring(start, end + 1);
  const decoded = JSON.parse(snippet);
  if (!decoded || typeof decoded !== "object" || Array.isArray(decoded)) {
    throw new Error("json_not_object");
  }
  return decoded as Record<string, unknown>;
}

/** Call Gemma 4 (multimodal) or Gemma 3 (text-only). */
async function callGemmaApi(
  apiKey: string,
  model: string,
  promptText: string,
  imageBase64?: string,
  imageMimeType?: string
): Promise<Record<string, unknown>> {
  const uri = new URL(
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`
  );
  uri.searchParams.set("key", apiKey);

  // Build content parts — Gemma 4 supports image + text in the same turn.
  // Gemma 3 fallback is text-only; image is omitted automatically.
  const isGemma4 = model === GEMMA_4_MODEL;
  const textPart = { text: promptText };

  type Part = { text: string } | { inlineData: { mimeType: string; data: string } };
  const parts: Part[] = [];

  if (isGemma4 && imageBase64 && imageBase64.length > 0) {
    // Image comes first; Gemma 4 processes left-to-right.
    parts.push({
      inlineData: {
        mimeType: imageMimeType?.trim() || "image/jpeg",
        data: imageBase64,
      },
    });
  }
  parts.push(textPart);

  const reqBody = {
    contents: [{ parts }],
    generationConfig: {
      temperature: 0.2,
      maxOutputTokens: 600,
      topP: 0.9,
    },
  };

  const res = await fetch(uri.toString(), {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(reqBody),
  });

  const responseText = await res.text();
  if (!res.ok) {
    throw new Error(`Gemma API HTTP ${res.status}: ${responseText.slice(0, 240)}`);
  }
  return JSON.parse(responseText) as Record<string, unknown>;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return json(405, { error: "method_not_allowed" });
  }

  const apiKey = Deno.env.get("GEMMA_API_KEY")?.trim();
  if (!apiKey) {
    return json(500, {
      error: "server_misconfigured",
      detail: "Missing GEMMA_API_KEY — set via Supabase project secrets",
    });
  }

  const rawText = await req.text();
  if (rawText.length > MAX_BODY_CHARS) {
    return json(413, {
      error: "payload_too_large",
      max_chars: MAX_BODY_CHARS,
    });
  }

  let body: ReqBody;
  try {
    body = JSON.parse(rawText) as ReqBody;
  } catch {
    return json(400, { error: "invalid_json" });
  }

  const transcript = String(body.transcript ?? "").slice(0, 1400);
  const location = String(body.location ?? "");
  const severityHint = Number.isFinite(body.severity_hint as number)
    ? Math.max(1, Math.min(5, Number(body.severity_hint)))
    : 3;
  const languageCode = String(body.language_code ?? "en").slice(0, 8);

  // Vision input — only forwarded to Gemma 4 (multimodal).
  // Gemma 3 fallback receives text-only to avoid API errors.
  let imageBase64 = typeof body.image_base64 === "string" && body.image_base64.length > 0
    ? body.image_base64
    : undefined;
  if (imageBase64 && imageBase64.length > MAX_IMAGE_BASE64_CHARS) {
    return json(413, {
      error: "image_too_large",
      max_chars: MAX_IMAGE_BASE64_CHARS,
    });
  }
  const imageMimeType = body.image_type || "image/jpeg";
  const hasImage = !!imageBase64;

  const promptText = buildTextPrompt({
    transcript,
    location,
    severityHint,
    languageCode,
    hasImage,
  });

  let gemmaJson: Record<string, unknown>;
  let modelUsed = GEMMA_4_MODEL;
  let visionUsed = false;

  // Tier 1-A: Gemma 4 27B (multimodal — with crash scene photo if provided)
  try {
    gemmaJson = await callGemmaApi(apiKey, GEMMA_4_MODEL, promptText, imageBase64, imageMimeType);
    visionUsed = hasImage;
  } catch (e) {
    console.warn(`Gemma 4 (${GEMMA_4_MODEL}) failed, trying fallback:`, e);
    // Tier 1-B: Gemma 3 27B (text-only — drop image)
    try {
      gemmaJson = await callGemmaApi(apiKey, GEMMA_3_FALLBACK, promptText);
      modelUsed = GEMMA_3_FALLBACK;
    } catch (e2) {
      console.error(`Fallback model ${GEMMA_3_FALLBACK} also failed:`, safeDetail(e2));
      return json(502, {
        error: "gemma_fetch_failed",
        models_tried: [GEMMA_4_MODEL, GEMMA_3_FALLBACK],
      });
    }
  }

  try {
    const modelOutputText = extractModelText(gemmaJson);
    const payload = extractFirstJsonObject(modelOutputText);
    return json(200, {
      ...payload,
      _model: modelUsed,
      _vision_used: visionUsed,
    });
  } catch (e) {
    console.error("gemma_parse_failed:", safeDetail(e));
    return json(502, {
      error: "gemma_parse_failed",
      model_used: modelUsed,
    });
  }
});
