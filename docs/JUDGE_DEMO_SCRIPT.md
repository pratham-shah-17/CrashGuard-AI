# Judge demo script — CrashGuard AI

Reproducible flow for hackathon / sponsor demos. Complete **pre-flight** before recording.

## Pre-flight (5–10 min)

1. **Device:** Mid-range Android (arm64) with **4+ GB RAM** for on-device Gemma demo.
2. **Network:** Have **Wi‑Fi + cellular** ready; also test **airplane mode** path separately.
3. **Secrets:** `.env` or `--dart-define`: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, optional `POWERSYNC_URL`, `SMS_DISPATCH_URL` / relay URL — confirm Twilio/Edge secrets live on Supabase for Tier 1 + SMS.
4. **Gemma E4B:** Complete **model download** (`GemmaModelManager` / onboarding) before offline segments — otherwise Tier 3–4 show honestly.
5. **Permissions:** Location, SMS (Android), Bluetooth — grant before demo.
6. **Legal:** Open **Privacy / consent** once if required by build.

## Demo A — Online “full stack” (3 min)

| Step | Action | Expected result |
|------|--------|-----------------|
| 1 | Open app → Dashboard | Driving banner may show if moving |
| 2 | Tap **SOS** | Countdown appears; can cancel with large control |
| 3 | Let countdown complete or confirm | Phase moves GPS → triaging |
| 4 | Speak / type scenario (or use preset) | Triage card shows severity + services |
| 5 | Observe **Dispatch status** panel | SMS / mesh / DB rows show **pending → success/failed** (honest states) |
| 6 | Open **AI explainability** (if exposed on card) | Tier label matches cloud / on-device / heuristic |

**Wow line:** “Tier 1 Gemma 4 27B with optional crash photo — server-side key, structured JSON, validation agent overrides unsafe outputs.”

## Demo B — Offline / resilience (2 min)

| Step | Action | Expected result |
|------|--------|-----------------|
| 1 | Enable **airplane mode** | Connectivity indicator offline |
| 2 | Trigger SOS | Tier 1 skips or fails fast; **Tier 2** if model present, else Tier 3–4 |
| 3 | Read triage source label | Must **not** claim “cloud” when offline |

**Wow line:** “Same orchestrator — graceful degradation; dispatch still attempts SMS/BLE per policy.”

## Demo C — Family link (1 min)

| Step | Action | Expected result |
|------|--------|-----------------|
| 1 | Complete SOS with GPS | Family SMS or link path per profile |
| 2 | Open tracking URL in **browser** (incognito) | Map or JSON per `family-track` — **no app install** |

## What not to claim live

- **iOS background crash** parity with Android — say “limited by OS policy” (`docs/project-history/AUDIT_REPORT.md`).
- **BLE mesh** — “bonus when nearby users have the app”; not a substitute for 108/112/SMS.
- **Medical diagnosis** — triage is **decision support**, not a clinician.

## Backup if API fails

Show **dispatch panel** + **Tier 3/4** triage + **recorded screen capture** from a good run — judges forgive infra if story is honest.
