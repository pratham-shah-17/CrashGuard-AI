# Platform matrix — CrashGuard AI

What works **where**, for judges and PMs. Update when adding native features.

## Android

| Area | Status | Notes |
|------|--------|-------|
| SOS / orchestrator | **Supported** | Primary target |
| Crash detection (accel + GPS + stillness) | **Supported** | Foreground service path |
| Background crash | **Partial** | OS limits; see `docs/project-history/AUDIT_REPORT.md` |
| Automated SMS (Twilio relay) | **Supported** | Needs Edge + secrets |
| Direct SMS fallback | **Supported** | Permission-dependent |
| BLE mesh / radar | **Supported** | Foreground service helps scanning |
| On-device Gemma (Tier 2) | **Supported** | Large model download |
| PowerSync / SQLite | **Supported** | |
| Maps / offline tiles | **Supported** | |

## iOS

| Area | Status | Notes |
|------|--------|-------|
| SOS / orchestrator | **Supported** | |
| Crash detection | **Partial** | Stricter background limits; no third-party “Car Crash” API |
| BLE | **Partial** | Background scanning constrained |
| On-device Gemma | **Supported** | If `flutter_gemma` + model on device |
| SMS automation | **Partial** | No silent SMS like Android; rely on relay + `tel:` / user prompts per policy |
| PowerSync | **Supported** | |

## Web (Flutter web)

| Area | Status | Notes |
|------|--------|-------|
| UI / demo | **Partial** | Good for marketing demo HTML (`demo/index.html`) |
| On-device Gemma Tier 2 | **Not available** | `GemmaLocalService` exits early on web |
| BLE / SMS native | **Not available** | Use hosted demo for AI story only |

## Honest one-liner

**Ship the hackathon story on Android physical devices**; use **web** for lightweight Gemma triage demo; treat **iOS** as real but **not feature-equal** for background mesh/SMS.
