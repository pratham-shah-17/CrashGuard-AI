# Security Policy

## Supported Versions

CrashGuard AI is pre-1.x and does not yet maintain parallel release branches.
Security fixes land on `main` and the latest tagged release; only the most
recent release receives patches.

| Version | Supported          |
| ------- | ------------------ |
| latest  | :white_check_mark: |
| older   | :x:                |

## Reporting a Vulnerability

If you discover a security vulnerability within CrashGuard AI, please send an e-mail to security@crashguard.ai rather than opening a public issue. All security vulnerabilities will be promptly addressed.

Please include:
- A description of the vulnerability.
- Steps to reproduce.
- Potential impact.

## Threat Model

CrashGuard AI handles emergency dispatch for potentially unconscious victims, so
the primary threats are: (1) an attacker preventing a real SOS from firing,
(2) an attacker triggering false SOS floods, and (3) leaking a victim's
real-time location or medical data.

| Surface | Risk | Mitigation |
|---|---|---|
| BLE mesh beacon | Spoofed or replayed SOS beacons | AES-GCM encrypted payload; nonce per broadcast |
| Supabase Realtime channel | Unauthorized read of nearby SOS events | Row Level Security (RLS) policies scope reads to the emergency's participants |
| SMS dispatch | Twilio credentials on device | Dispatch runs server-side via a Supabase Edge Function — no Twilio key ever ships in the app |
| AI triage (cloud tier) | Prompt injection via bystander voice/photo input | Structured JSON output schema; severity/service fields are validated, not freeform-executed |
| On-device AI (Gemma 4 E4B) | Model tampering / supply chain | Model downloaded once from HuggingFace over HTTPS during onboarding, with a file-integrity size check before use (see `gemma_local_service.dart`) |
| Location data | Continuous GPS tracking beyond the emergency window | Location is only persisted for the duration of an active SOS/Safe Walk session |

## Encryption & Privacy

- **BLE mesh**: 256-bit AES-GCM for all peer-to-peer beacon traffic.
- **Offline-first storage**: emergency and profile data lives in local SQLite
  (via PowerSync) and only syncs to Supabase when connectivity is available —
  no data leaves the device while offline.
- **On-device AI (Tier 2–4)**: triage inference for Gemma 4 E4B, the
  heuristic model, and the keyword classifier all run locally; no request
  leaves the device for these tiers.
- **Cloud AI (Tier 1)**: only the crash-scene photo and voice transcript
  needed for triage are sent to the Supabase Edge Function; no persistent
  chat history is retained by the model provider.
- **API keys**: Supabase anon key ships in the client by design (RLS-scoped);
  Twilio and Gemma cloud credentials are server-side only and never bundled
  into the app.

This threat model is a living document — please open an issue or email
security@crashguard.ai if you believe a surface above is missing or
under-mitigated.
