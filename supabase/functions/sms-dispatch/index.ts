/**
 * Supabase Edge Function: sms-dispatch
 *
 * Server-side automated SMS dispatch — no user interaction required.
 * Sends emergency SMS via Twilio WITHOUT requiring the victim to tap send.
 * This is the critical fix for unconscious/trapped victims.
 *
 * Supports:
 * - Twilio SMS API (primary)
 * - Direct Indian ERSS relay (secondary, if configured)
 *
 * Secrets required (set in Supabase project):
 * - TWILIO_ACCOUNT_SID
 * - TWILIO_AUTH_TOKEN
 * - TWILIO_FROM_NUMBER  (your Twilio phone number, e.g. +1234567890)
 *
 * Optional:
 * - EMERGENCY_NUMBER_OVERRIDE  (override default 112)
 * - INDIA_ERSS_WEBHOOK_URL     (MHA/state ERSS webhook if enrolled)
 */
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

type ReqBody = {
  payload: string;
  latitude?: number;
  longitude?: number;
  severity_level?: number;
  required_services?: string[];
  country_code?: string;
  destination?: string;
};

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8" },
  });
}

function resolveEmergencyNumber(countryCode?: string, override?: string): string {
  if (override?.trim()) return override.trim();
  const uses911 = new Set(["US", "CA", "MX"]);
  if (countryCode && uses911.has(countryCode)) return "911";
  return "112";
}

function buildSmsBody(body: ReqBody, emergencyNumber: string): string {
  const loc =
    body.latitude != null && body.longitude != null
      ? `GPS: ${body.latitude.toFixed(5)},${body.longitude.toFixed(5)} `
      : "";
  const sev = body.severity_level != null ? `SEV:${body.severity_level}/5 ` : "";
  const svcs = body.required_services?.length
    ? `NEEDS: ${body.required_services.join(",").toUpperCase()} `
    : "";
  const maps =
    body.latitude != null && body.longitude != null
      ? `maps.google.com/?q=${body.latitude.toFixed(5)},${body.longitude.toFixed(5)}`
      : "";

  const core = `RoadSOS EMERGENCY ${sev}${svcs}${loc}${maps}`.trim();
  return core.slice(0, 1500);
}

async function sendViaTwilio(
  accountSid: string,
  authToken: string,
  from: string,
  to: string,
  body: string
): Promise<{ ok: boolean; detail: string }> {
  const url = `https://api.twilio.com/2010-04-01/Accounts/${accountSid}/Messages.json`;
  const params = new URLSearchParams({
    From: from,
    To: to,
    Body: body,
  });

  const credentials = btoa(`${accountSid}:${authToken}`);
  const res = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Basic ${credentials}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: params.toString(),
  });

  const respText = await res.text();
  if (res.ok) {
    let sid = "";
    try {
      sid = (JSON.parse(respText) as any)?.sid ?? "";
    } catch (_) {}
    return {
      ok: true,
      detail: `Twilio accepted SMS to ${to}. SID: ${sid}. Carrier delivery not confirmed.`,
    };
  }
  return {
    ok: false,
    detail: `Twilio error ${res.status}: ${respText.slice(0, 300)}`,
  };
}

async function notifyErss(
  webhookUrl: string,
  body: ReqBody,
  emergencyNumber: string
): Promise<void> {
  try {
    await fetch(webhookUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        schema: "roadsos.erss.v1",
        latitude: body.latitude,
        longitude: body.longitude,
        severity_level: body.severity_level,
        required_services: body.required_services,
        emergency_number: emergencyNumber,
        timestamp: new Date().toISOString(),
      }),
    });
  } catch (e) {
    console.warn("ERSS webhook failed (non-fatal):", e);
  }
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return json(405, { error: "method_not_allowed" });
  }

  const twilioSid = Deno.env.get("TWILIO_ACCOUNT_SID")?.trim();
  const twilioToken = Deno.env.get("TWILIO_AUTH_TOKEN")?.trim();
  const twilioFrom = Deno.env.get("TWILIO_FROM_NUMBER")?.trim();

  if (!twilioSid || !twilioToken || !twilioFrom) {
    return json(500, {
      error: "server_misconfigured",
      detail: "Missing TWILIO_ACCOUNT_SID / TWILIO_AUTH_TOKEN / TWILIO_FROM_NUMBER",
    });
  }

  let body: ReqBody;
  try {
    body = (await req.json()) as ReqBody;
  } catch {
    return json(400, { error: "invalid_json" });
  }

  if (!body.payload) {
    return json(400, { error: "missing_payload" });
  }

  const emergencyNumber = resolveEmergencyNumber(
    body.country_code,
    body.destination ?? Deno.env.get("EMERGENCY_NUMBER_OVERRIDE")
  );

  const smsBody = buildSmsBody(body, emergencyNumber);

  const erssUrl = Deno.env.get("INDIA_ERSS_WEBHOOK_URL")?.trim();
  if (erssUrl) {
    notifyErss(erssUrl, body, emergencyNumber);
  }

  const result = await sendViaTwilio(
    twilioSid,
    twilioToken,
    twilioFrom,
    emergencyNumber,
    smsBody
  );

  if (result.ok) {
    return json(200, {
      ok: true,
      destination: emergencyNumber,
      detail: result.detail,
    });
  }

  return json(502, {
    ok: false,
    destination: emergencyNumber,
    detail: result.detail,
  });
});
