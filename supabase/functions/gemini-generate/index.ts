/**
 * Supabase Edge Function: gemma-generate
 *
 * Server-side Gemma 4 proxy for non-triage text generation
 * (witness interview questions, scene summaries, assistant responses).
 * Clients never hold Gemma/Gemini API keys.
 *
 * Secret required:
 * - GEMMA_API_KEY  (Google AI Studio API key)
 */
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const DEFAULT_MODEL = "gemma-4-27b-it";
const FALLBACK_MODEL = "gemma-3-27b-it";

type ReqBody = {
  prompt?: string;
  model?: string;
  temperature?: number;
  max_output_tokens?: number;
};

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8" },
  });
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
    if (p && typeof p === "object" && typeof (p as any)["text"] === "string") {
      out += String((p as any)["text"]);
    }
  }
  return out;
}

async function callGemma(
  apiKey: string,
  model: string,
  prompt: string,
  temperature: number,
  maxOutputTokens: number
): Promise<string> {
  const uri = new URL(
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`
  );
  uri.searchParams.set("key", apiKey);

  const res = await fetch(uri.toString(), {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      contents: [{ parts: [{ text: prompt }] }],
      generationConfig: { temperature, maxOutputTokens },
    }),
  });

  const text = await res.text();
  if (!res.ok) {
    throw new Error(`Gemma HTTP ${res.status}: ${text.slice(0, 500)}`);
  }
  const decoded = JSON.parse(text) as Record<string, unknown>;
  return extractModelText(decoded).trim();
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return json(405, { error: "method_not_allowed" });
  }

  const apiKey = Deno.env.get("GEMMA_API_KEY")?.trim();
  if (!apiKey) {
    return json(500, {
      error: "server_misconfigured",
      detail: "Missing GEMMA_API_KEY",
    });
  }

  let body: ReqBody;
  try {
    body = (await req.json()) as ReqBody;
  } catch {
    return json(400, { error: "invalid_json" });
  }

  const prompt = String(body.prompt ?? "").slice(0, 6000);
  if (!prompt) return json(400, { error: "missing_prompt" });

  const requestedModel = String(body.model ?? DEFAULT_MODEL).trim() || DEFAULT_MODEL;
  const model = requestedModel.startsWith("gemma") ? requestedModel : DEFAULT_MODEL;
  const temperature = typeof body.temperature === "number" ? body.temperature : 0.3;
  const maxOutputTokens =
    typeof body.max_output_tokens === "number" ? body.max_output_tokens : 512;

  try {
    const out = await callGemma(apiKey, model, prompt, temperature, maxOutputTokens);
    return json(200, { text: out, model_used: model });
  } catch (e) {
    console.warn(`Primary model ${model} failed, trying ${FALLBACK_MODEL}:`, e);
    try {
      const out = await callGemma(
        apiKey,
        FALLBACK_MODEL,
        prompt,
        temperature,
        maxOutputTokens
      );
      return json(200, { text: out, model_used: FALLBACK_MODEL });
    } catch (e2) {
      console.error(`Fallback model ${FALLBACK_MODEL} also failed:`, e2);
      return json(502, {
        error: "gemma_fetch_failed",
      });
    }
  }
});
