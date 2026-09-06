# CrashGuard AI · Blueprint — Gap Analysis (reconciled with code, May 2026)

Honest mapping of the product blueprint to this repository (`lib/`, `supabase/`). Status is **Real** (implemented end-to-end), **Partial** (env-gated, platform-specific, or incomplete vs blueprint), or **Not started** (spec only).

**Canonical implementation references:** `lib/services/ai_triage_service.dart` (4-tier Gemma stack), `lib/services/gemma_local_service.dart` (Tier 2 on-device), `supabase/functions/triage-gemini/index.ts` (Tier 1 cloud + vision), `docs/project-history/AUDIT_REPORT.md` (issue ledger).

---

## Visual & UX (Section 01 / 04)

| Blueprint item | Status | Notes |
|----------------|--------|-------|
| Emergency-grade dark UI (Abyss, Blood Red, Mesh Teal) | **Partial → Real** | `RoadSosTokens` / `roadsos_theme.dart`; SOS high-contrast path |
| Bebas Neue + Noto Sans + DM Mono | **Partial** | `google_fonts`; confirm font licenses before store submission |
| 56px min tap targets, 160px SOS, 8px grid | **Partial** | Tokens exist; per-screen audit still useful |
| No gradients in UI (maps excluded) | **Partial** | Theme avoids gradients; map layers excluded |
| Sub-100ms SOS path | **Partial** | No blocking animations on critical path; **not benchmarked in CI** |

---

## Phase 1 — Foundation

| Blueprint item | Status | Notes |
|----------------|--------|-------|
| Gemma 4 on-device (GGUF / LiteRT) | **Real** | Tier 2: `gemma-4-e4b-it` via `flutter_gemma` / MediaPipe LiteRT — `GemmaLocalService` |
| Cloud triage | **Real** | Tier 1: `gemma-4-27b-it` + optional vision in `triage-gemini` Edge Function |
| Tier 3–4 fallbacks | **Real** | `Tier2LocalTriageModel` + `OfflineTriageClassifier` in `ai_triage_service.dart` |
| 90s onboarding + medical profile | **Partial** | Onboarding + profile exist; full 4-step blueprint not fully verified |
| Crash: accel + GPS + stillness | **Partial** | `CrashDetectionService` + remote `crash_config` — **no mic, no S–G filter, no per-device calibration UI** |
| Panic SOS: cancel, haptics | **Partial** | Countdown + cancel; gesture spec may differ from blueprint |
| Family tracking URL (24h) | **Real** | `incident_live_links` + `family-track` + `FamilyTrackingService` |
| Live contact SMS verification | **Not started** | Free-text contact; no OTP |

---

## Phase 2 — Wow features

| Blueprint item | Status | Notes |
|----------------|--------|-------|
| Mesh visualiser | **Partial** | `mesh_radar.dart` + BLE pipeline; not full blueprint graph |
| AI triage voice (TTS/STT) | **Partial** | `voice_assistant_service` — depth varies by flow |
| Ephemeral mesh / scene keys | **Partial** | `SceneSecurityService` — compare to blueprint “per-incident rotation” |
| 12 Indian languages | **Partial** | **6** ARB locales: `en`, `hi`, `ta`, `mr`, `bn`, `te` |
| Bystander mode | **Partial** | Orchestrator + BLE; “non-dismissible” UX TBD |
| Ambient drive detection | **Partial** | `proactive_monitor_service` / heuristics |

---

## Phase 3 — Network & scale

| Blueprint item | Status | Notes |
|----------------|--------|-------|
| 112 ERSS API | **Partial** | Optional `INDIA_ERSS_API_URL` in SMS path — enrollment-specific |
| Responder dashboard | **Partial** | `responder_dashboard.dart` (in-app) |
| Battery tier architecture | **Not started** | Spec only |
| Driving score / hazards / freemium | **Not started** | Spec only |

---

## Phase 4 — Launch & judges

| Blueprint item | Status | Notes |
|----------------|--------|-------|
| Play Store / App Store | **Not started** | `publish_to: 'none'` is pub.dev only; store listing separate |
| Automated quality gate | **Real** | GitHub Actions: `dart analyze` + `flutter test` (see `.github/workflows/flutter_ci.yml`) |
| E2E benchmark suite | **Partial** | Unit/widget tests; full E2E on device not in CI |
| Case-study video | **Out of repo** | `docs/VIDEO_SCRIPT.md` + manual production |

---

## Flagship claims (Section 03)

| Claim | Status | Notes |
|-------|--------|-------|
| Encrypted BLE mesh | **Partial** | AES-GCM helpers + advertising; multi-hop “relay” not production-complete |
| On-device Gemma triage | **Real** | Tier 2 when model downloaded; else falls through to Tier 3–4 |
| Bystander network | **Partial** | BLE + orchestration; both devices need app for full mesh value |
| Family link without app install | **Real** | Browser `family-track` |
| Rich sensor crash pipeline | **Partial** | Accel + GPS + stillness + optional gyro validation — not full triple-sensor blueprint |
| Battery &lt;5%/hr passive | **Not started** | Needs field measurement |

---

## Maintenance

- Revisit this file when merging **triage, dispatch, or schema** changes.
- Keep **Real vs Simulated** honest for judges and `docs/DEVELOPMENT_RULEBOOK.md` Phase 8.
- **Do not** reintroduce outdated rows (“Gemini HTTP only”, “no on-device Gemma”) without verifying `ai_triage_service.dart` and `gemma_local_service.dart`.
