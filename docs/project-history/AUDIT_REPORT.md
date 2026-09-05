# Audit Report: CrashGuard AI (Updated May 2026)

This document tracks identified issues and their resolution status.

---

## Sprint round (May 17, 2026) — "functionally dumb features" pass

Brutal audit by the user: "go through the code and think of a person in a
situation of an accident and see if it really helps". The following landmines
were found and fixed across four agile sprints on branch
`cursor/foolproof-features-and-gemma4-everywhere-bb8f`.

### CRITICAL — Sprint 1
- ✅ **Fake "nearby services broadcast" success** — `EmergencyOrchestrator`
  used `Future.delayed(3s, () => true)` for the `nearby_services` dispatch
  channel. UI claimed "Emergency alert broadcasted to nearby facilities ✓"
  while nothing was sent. Replaced with `NearbyServicesBroadcastService`
  that publishes on the Supabase Realtime channel `roadsos_nearby_sos`
  (the same channel the bystander FCM relay was designed to mirror).
  Reports honest typed outcomes (`ok` / `skipped — not signed in` /
  `skipped — offline` / `failed`) with hard subscribe + send timeouts.
- ✅ **Auto-SOS triage was text-only despite "+vision" marketing** —
  `AiTriageService.triageEmergency()` hardcoded `scenePhoto = null`. Vision
  only worked through the unused `triageWithScenePhoto()` API. New
  `LastScenePhotoStore` is populated by Capture Scene and pulled by the
  orchestrator (fresh ≤ 120 s) so the Gemma 4 27B vision tier actually
  fires during real SOS. Stash is cleared after every dispatch.
- ✅ **Hardcoded severity hint of 3 / 4** — `performTriage` and the safety
  validator both received a constant severity hint regardless of how
  violent the detected crash was. Crash detector now stashes
  `CrashConfidenceResult` and exposes `recentSeverityHint()` (1..5, 30 s
  freshness). Orchestrator forwards that value to both `performTriage()`
  and `triageValidationAgent.validate(accelSeverityHint:)`.

### HIGH — Sprint 2 (push Gemma 4 deeper)
- ✅ **Structured 112 SMS vitals slot always literal `C?B?Bl?`** — now reads
  from `vitalSignsProvider` and renders `H120,R28,O88` when the bystander
  entered them in Vital Scan. Falls back to `?` triplet only when nothing
  has been entered.
- ✅ **AgentHealthService.gemmaCloud lied** — it mirrored connectivity
  state and returned "ready" on Wi-Fi even when the Edge Function was
  down. Now issues a tiny HEAD probe to the actual `triage-gemini`
  endpoint with a 2.5 s timeout, cached for 25 s.
- ✅ **RoadSosAssistantService scene detection was keyword matching** —
  Hindi / mixed Hindi-English mostly landed in `unknown`. Now Gemma 4 27B
  classifies first; keyword matcher is offline fallback only. The FIRST
  interview question is also Gemma-composed (was previously a hardcoded
  line from the canned 5-question script).

### HIGH — Sprint 3 (radar + UI honesty)
- ✅ **Bystander radar plotted hashCode-fake positions** — every peer dot
  was placed at `angle = id.hashCode`. Now plots real
  `(bearing, distance)` from the BLE-decoded lat/lng vs the device's own
  GPS fix, with a soft logarithmic distance scale. Falls back to an
  RSSI-based ring and tells the user "GPS unavailable — peer angles
  approximate" when GPS is missing. Dots are colour-coded by decoded
  severity. Stale peers expire after 45 s.
- ✅ **Misleading dashboard subtitles** — "Capture Scene: AI-powered photo
  analysis" (which did nothing), "Responder View: live map with nearby
  SOS signals" (no third-party feed), "Vital Scan: check heart rate &
  oxygen saturation" (no rPPG). All three subtitles now match the
  honest behaviour and reference the fix from Sprint 1.

### MEDIUM — Sprint 4 (Gemma 4 in first aid + honest comments)
- ✅ **First Aid screen showed raw FTS rows** — now
  `FirstAidRepository.lookupWithGemma(query, languageCode)` performs RAG:
  retrieves grounding from the SQLite FTS5 corpus, asks Gemma 4 27B
  (cloud) for 1–6 calm, locale-correct numbered steps, with hard
  constraints (no invented steps, no doses, life-threatening cases force
  "call 108 first"). Falls back to the raw corpus row when cloud is down.
- ✅ **`EmergencyBeaconService` comment claimed "Gemma 4 agent takes over"** —
  there is no ML on that path. Comment now matches reality (it's a pure
  flashlight strobe + synthesised audio tone driver).
- ✅ **`TriageFeedbackService` was labelled "RL-based optimisation"** —
  oversell. The implementation is an EMA over a user-supplied severity
  bias, bounded to [−1.0, +1.0], and never touches model weights.
  Re-documented as "bounded preference calibration".
- ✅ **`MultiAgentCoordinator` was unused infrastructure** —
  it was not wired into the SOS pipeline. Removed.
- ✅ **Mesh chat collided with SOS BLE channel** —
  Mesh chat is now actively disabled and exits automatically when `SOSPhase != idle`.
- ✅ **`SafeWalk` timer-only mode was brittle** —
  now requires explicit user acknowledgment when no destination coordinates are supplied.

### Verification
- `flutter analyze` — **No issues found!**
- `flutter test` — **17 tests pass** (3.41.9 / Dart 3.11.5).

---

## Critical Issues — RESOLVED

### ✅ FIXED: Used Gemini Flash instead of Gemma 4
**Was:** `gemini-2.0-flash` (closed proprietary model — not Gemma)
**Fix:** All AI inference now uses `gemma-4-27b-it` (cloud) and `gemma-4-e4b-it` (on-device).
- `supabase/functions/triage-gemini/index.ts` — updated to `gemma-4-27b-it` with `gemma-3-27b-it` fallback
- `supabase/functions/gemini-generate/index.ts` — updated to `gemma-4-27b-it`
- `lib/services/gemini_http.dart` — updated model default
- `lib/services/ai_triage_service.dart` — rebuilt as 4-tier Gemma 4 pipeline

### ✅ FIXED: On-device AI was keyword matching, not a model
**Was:** `OfflineTriageClassifier` — pure string `.contains()` checks
**Fix:** Added `GemmaLocalService` — Gemma 4 E4B (Edge 4B) via `flutter_gemma` / LiteRT as Tier 2. Keyword classifier is now Tier 4 (last resort only). See `lib/services/gemma_local_service.dart`.

### ✅ FIXED: SMS dispatch required user to tap send
**Was:** `url_launcher` opening `sms:112` URI — requires conscious user.
**Fix:** Added `supabase/functions/sms-dispatch/index.ts` — Twilio-based server-side SMS dispatch. No user interaction required. Works even if victim is unconscious. Android direct SEND_SMS remains as device-level fallback.

### ✅ FIXED: Supabase auth was silently failing
**Was:** `currentSession` always null — PowerSync never synced.
**Fix:** `lib/database/app_database.dart` already has `signInAnonymously()` — verified present and correct. Documented clearly.

### ✅ FIXED: Client was directly querying Overpass API (ToS violation at scale)
**Was:** Mobile client calling `overpass-api.de` directly.
**Fix:** `lib/services/facility_sync_service.dart` — no client Overpass queries. `supabase/functions/sync-osm-facilities/index.ts` runs server-side (cron job). Clients receive data via PowerSync.

### ✅ FIXED: First Aid "RAG" was 5 hardcoded strings
**Was:** Literal dictionary of 5 strings.
**Fix:** `lib/services/first_aid_repository.dart` uses SQLite FTS5 full-text search against the bundled `assets/first_aid/corpus.json`. Token scoring fallback for web.

### ✅ FIXED: Hardcoded credentials in source
**Was:** Supabase URL/key in Dart source code.
**Fix:** All credentials via `flutter_dotenv` (`.env` file, never committed) or `--dart-define` in CI. Supabase function secrets (GEMMA_API_KEY, Twilio) never reach the client.

---

## High Issues — RESOLVED

### ✅ FIXED: No GEMMA_API_KEY env var
**Fix:** `assets/env.template` updated with clear documentation. Edge functions use `GEMMA_API_KEY` (set as Supabase secret, never on client).

### ✅ FIXED: Overpass API would get IP-banned at scale
**Fix:** Server-side cron via `sync-osm-facilities` edge function. PowerSync replicates to clients.

---

## Automation

- **CI:** `.github/workflows/flutter_ci.yml` runs `dart analyze` + `flutter test` on every push/PR to `main`.
- **Docs:** `docs/BLUEPRINT_GAP_ANALYSIS.md` is reconciled with the Gemma 4 stack — do not revert outdated “Gemini-only” rows without verifying code.

## Remaining Known Gaps (not blocking hackathon submission)

### 🔶 Background crash detection reliability
- **Android**: Multi-stage crash detection (accel + GPS speed + stillness) works with foreground service.
- **iOS**: Severely limited by OS background execution policy. System Crash Detection (Apple) is not exposed to third-party apps. CrashGuard AI crash detection works while app is active.
- **Fix priority**: Post-hackathon — requires iOS background mode entitlements review.

### 🔶 BLE mesh requires both devices to have app running
- Background BLE scanning on iOS requires specific entitlements.
- Android foreground service can keep scanning alive.
- **Impact**: Mesh is a "bonus channel" — SMS dispatch via Twilio is the primary automated path.

### 🔶 On-device Gemma 4 E4B requires ~2.4 GB download
- Model must be pre-downloaded during onboarding.
- For hackathon demo: pre-load the model file before recording.
- Long-term: progressive download with delta updates.

### 🔶 No Play Store / App Store listing
- `publish_to: 'none'` is for pub.dev package publishing, not app stores.
- App store submission requires privacy review, medical disclaimer, and production Supabase setup.

### 🔶 No professional human dispatch loop
- Currently: automated SMS to 112 + Twilio relay.
- Missing: confirmed callback from dispatch center.
- Long-term: API partnership with India's ERSS/112 system.

---

## Architecture Summary (Post-Fix)

```
SOS Trigger (tap / crash detection)
    ↓
EmergencyOrchestrator
    ↓ [parallel]
┌─────────────────────────────────────┐
│ Gemma 4 Triage Stack                │
│   Tier 1: gemma-4-27b-it (cloud)   │ ← 3s timeout
│   Tier 2: gemma-4-e4b-it (device)  │ ← 8s timeout, offline-capable
│   Tier 3: Weighted heuristic        │ ← always available
│   Tier 4: Keyword classifier        │ ← last resort
└─────────────────────────────────────┘
    ↓
┌─────────────────────────────────────┐
│ Dispatch Channels (parallel)        │
│   SMS: Twilio edge fn (automated)  │ ← no user tap needed
│   SMS: Android SEND_SMS (fallback) │
│   BLE: Encrypted mesh beacon       │
│   DB: PowerSync → Supabase         │
│   Family: tracking link            │
└─────────────────────────────────────┘
```
