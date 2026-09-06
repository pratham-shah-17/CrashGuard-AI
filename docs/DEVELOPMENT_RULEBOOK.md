# CrashGuard AI — Master Development Rulebook

> **200+ rules across 9 phases of development.**  
> Tags: `[CRITICAL]` `[COLLAB]` `[INDIA]` `[AI/ML]` `[SECURITY]`  
> A rule tagged `[CRITICAL]` means the app either fails, creates legal liability, or risks lives if ignored.

---

## How to use this document

- Work through phases in order — Phase 1 and Phase 5 before writing any code.
- In code review, the reviewer must check every `[CRITICAL]` rule for the files touched in the PR.
- This file lives in `docs/`. Update it when new rules are agreed upon in architecture syncs.
- Every rule that is "done" for your current sprint can be marked with `[x]` in your local copy.

---

## Phase 1 — Planning

### Product scope

- [ ] Every feature must answer: **does this work when the user is unconscious?** `[CRITICAL]`
- [ ] Define the minimum viable SOS flow before any other feature is scoped. `[CRITICAL]`
- [ ] Explicitly document what the app does NOT do — false claims are a life-safety risk. `[CRITICAL]`
- [ ] Write a one-page "failure modes" doc listing every way the app could fail silently. `[CRITICAL]`
- [ ] Maintain a feature flag registry so experimental features are off by default in release builds.
- [ ] For every promised feature, write a testable acceptance criterion before development starts. `[COLLAB]`
- [ ] Hold a "kill feature" review every sprint — remove anything that cannot be made real within 2 sprints.
- [ ] Mark every feature as: **Real / Simulated / Planned** — never ship Simulated features as Real. `[CRITICAL]`

### India-specific planning

- [ ] Define the target device profile: assume 3 GB RAM, MediaTek G85, Android 12, budget screen. `[INDIA]`
- [ ] List all 5 regional languages your first launch must support (minimum: Hindi, Tamil, Bengali, Telugu, Marathi). `[INDIA]`
- [ ] Map every emergency contact to the correct Indian authority: 112 (national), 108 (ambulance), 100 (police), 101 (fire). `[INDIA]` `[CRITICAL]`
- [ ] Research and document the DPDP Act 2023 obligations for the data you collect before writing any data model. `[INDIA]` `[SECURITY]`
- [ ] Identify rural vs urban connectivity scenarios — design for 2G EDGE as the baseline, not 4G. `[INDIA]`
- [ ] Plan for MapmyIndia SDK integration rather than OSM tiles from day one. `[INDIA]`

### Collaboration setup

- [ ] Create a branch protection rule on `main`: no direct pushes, all merges require at least one review. `[COLLAB]`
- [ ] Write a `CONTRIBUTING.md` that defines: branch naming, commit message format, PR template, review SLA. `[COLLAB]`
- [ ] Define a Definition of Done: code reviewed, tests passing, lint clean, acceptance criterion verified. `[COLLAB]`
- [ ] Set up a project board (GitHub Projects / Linear) with columns: Backlog → In Progress → In Review → Done. `[COLLAB]`
- [ ] Assign a module owner to each `lib/` subfolder — one person is the final reviewer for their module. `[COLLAB]`
- [ ] Schedule a weekly 30-minute architecture sync to prevent silent structural drift. `[COLLAB]`

---

## Phase 2 — Architecture

### Service design

- [ ] Each service class has exactly one responsibility — `EmergencyOrchestrator` must not parse GPS data.
- [ ] Define all inter-service contracts (input/output types) in abstract interfaces before writing implementations. `[COLLAB]`
- [ ] The emergency dispatch pipeline must be synchronous and blocking — no fire-and-forget in a life-safety path. `[CRITICAL]`
- [ ] Every service must expose a `isReady()` or `healthCheck()` method so the orchestrator can verify state before dispatching. `[CRITICAL]`
- [ ] Services must never throw uncaught exceptions — all errors must be returned as typed `Result` objects.
- [ ] The offline path must be independently testable without any network or BLE hardware. `[CRITICAL]`
- [ ] Write the state machine diagram (`Idle → Countdown → Triaging → Active → Resolved`) before coding `EmergencyOrchestrator`.

### Data architecture

- [ ] Use one SQLite database (PowerSync) — remove `sqflite` from `pubspec.yaml` entirely. One source of truth. `[CRITICAL]`
- [ ] Define every Supabase table schema in a migrations file committed to the repo before any data is written. `[COLLAB]`
- [ ] Every sensitive field (blood group, medical notes, GPS history) must be encrypted at rest using `flutter_secure_storage`. `[SECURITY]`
- [ ] Never store raw GPS coordinates in plaintext in local SQLite — encrypt before writing. `[SECURITY]`
- [ ] Define data retention policies in code: auto-delete incident records older than 90 days via Supabase cron. `[INDIA]` `[SECURITY]`
- [ ] Implement Row Level Security on all Supabase tables before any production data is written. `[SECURITY]` `[CRITICAL]`
- [ ] Pre-bundle the NHM hospital dataset as a seeded SQLite asset — never fetch it on first launch. `[INDIA]`

### Offline architecture

- [ ] Define the exact offline capability matrix: what works with no data, no BLE, no GPS — document it. `[CRITICAL]`
- [ ] USSD-based SOS must be the primary offline fallback — not BLE mesh. Wire it before any mesh work. `[INDIA]` `[CRITICAL]`
- [ ] Map tiles must be pre-cached on first launch over Wi-Fi using `flutter_map_tile_caching`, not fetched live. `[INDIA]`
- [ ] The AI triage fallback (heuristic/keyword) must work with zero network and zero LLM — test this explicitly. `[CRITICAL]`
- [ ] All outbound dispatch attempts must be queued to a local queue and retried on connectivity restore.

### AI / ML architecture

- [ ] Never load a model >200 MB on-device for Indian target hardware — use cloud LLM as primary. `[AI/ML]` `[INDIA]` `[CRITICAL]`
- [ ] AI triage has three tiers: (1) Cloud LLM, (2) TFLite/ONNX classifier <50 MB, (3) keyword heuristic. All three must be implemented. `[AI/ML]` `[CRITICAL]`
- [ ] The triage output must always be a structured typed object — never a raw string passed to the UI. `[AI/ML]`
- [ ] AI responses must include a confidence score — if below threshold, fall to the next tier automatically. `[AI/ML]`
- [ ] AI triage must be time-bounded: if no response in 3 seconds, fall to tier 2. If 6 seconds, fall to tier 3. Hard timeouts enforced. `[AI/ML]` `[CRITICAL]`
- [ ] Never claim "AI-powered" in UI copy unless tier 1 or tier 2 is actively running — show which tier is active. `[AI/ML]`
- [ ] Log every triage decision with its tier, input, and output for model evaluation and debugging. `[AI/ML]` `[COLLAB]`

---

## Phase 3 — Environment

### Secrets and environment

- [ ] Zero secrets in the codebase — Supabase `url`/`anonKey` must be in `.env`, loaded via `flutter_dotenv`. `[SECURITY]` `[CRITICAL]`
- [ ] `.env` must be in `.gitignore` — verify this with `git ls-files` before every commit. `[SECURITY]` `[CRITICAL]`
- [ ] Create a `.env.example` with all required keys and placeholder values — commit this file. `[COLLAB]`
- [ ] Use GitHub Secrets for all CI/CD environment variables — never paste secrets in workflow YAML. `[SECURITY]` `[COLLAB]`
- [ ] Rotate Supabase anon keys immediately if they are ever committed to git history, even briefly. `[SECURITY]`
- [ ] API keys for Gemini / Twilio / MapmyIndia must each have the minimum required permission scope only. `[SECURITY]`

### CI/CD pipeline

- [ ] CI must run on every PR: `flutter analyze`, `flutter test`, `dart format --check`. All three must pass for merge. `[COLLAB]` `[CRITICAL]`
- [ ] Add a secrets-scanning step (trufflehog or gitleaks) to CI — block merge if any secret pattern is found. `[SECURITY]` `[COLLAB]`
- [ ] Build the APK in CI on every PR — a PR that breaks the build cannot be merged. `[COLLAB]`
- [ ] Set up a dedicated staging Supabase project — never run tests against the production database. `[COLLAB]` `[SECURITY]`
- [ ] Tag every release build with a Git tag (`v1.0.0`) and generate a changelog from commit messages. `[COLLAB]`
- [ ] Run `flutter build apk --release` in CI to catch release-mode-only issues (ProGuard, tree-shaking).

### Code style

- [ ] `dart format` is non-negotiable — enforce it with `dart format --check` in CI, fail on diff. `[COLLAB]`
- [ ] `analysis_options.yaml` must enable: `avoid_print`, `prefer_final_fields`, `avoid_catches_without_on_clauses`. `[CRITICAL]`
- [ ] Replace every `print()` call with a logger package (`logger` or `talker`) — log level gated, stripped in release. `[CRITICAL]`
- [ ] Replace all `.withOpacity()` calls with `.withValues(alpha:)` — run a repo-wide find-and-replace now.
- [ ] Replace deprecated `userAccelerometerEvents` with `userAccelerometerEventStream()` in `crash_detection_service.dart`.
- [ ] No TODO comments in code without a linked GitHub issue number. TODOs without issues get deleted in review. `[COLLAB]`
- [ ] All public methods and all service classes must have a `///` dartdoc comment block. `[COLLAB]`
- [ ] Riverpod version must be a caret constraint (`^2.5.1`), not an exact pin (`2.5.1`).

---

## Phase 4 — Development

### Emergency dispatch

- [ ] Call `Supabase.instance.client.auth.signInAnonymously()` on app launch — before PowerSync initializes. `[CRITICAL]`
- [ ] The SOS button must be tappable within 1 second of app launch — measure this with a stopwatch widget test. `[CRITICAL]`
- [ ] All dispatch channels (SMS, BLE, Cloud) must be fired in parallel, not sequentially. `[CRITICAL]`
- [ ] Each dispatch channel must report back an explicit success or failure — never assume success. `[CRITICAL]`
- [ ] The SOS countdown timer must be cancellable by a single tap on a button that is at least 88×88 dp. `[CRITICAL]`
- [ ] After dispatch, write a local dispatch receipt to SQLite — even if cloud sync fails, the record exists locally.
- [ ] The `SEND_SMS` permission must be requested at the permissions onboarding screen, not on first SOS.
- [ ] For iOS: route emergency SMS via a backend Twilio function — document that iOS cannot send SMS in background. `[CRITICAL]`
- [ ] Implement USSD dialling (`tel:` scheme) as the absolute last-resort fallback — one tap to call 112. `[INDIA]` `[CRITICAL]`

### Crash detection

- [ ] Use three-stage detection: G-force spike (>20 G) + sustained stillness (>2 s) + GPS speed drop (>20 kph to 0 in <1.5 s). `[CRITICAL]` `[INDIA]`
- [ ] Add a 10-second grace window after crash detection before SOS fires — user must be able to cancel. `[CRITICAL]`
- [ ] Use `userAccelerometerEventStream()` — not the deprecated `userAccelerometerEvents`.
- [ ] Debounce accelerometer events — process one sample per 50 ms, not every raw event.
- [ ] Test crash detection on Indian road conditions: simulate a pothole (single spike, no stillness) — must NOT trigger. `[INDIA]` `[CRITICAL]`
- [ ] Crash detection must run in a dedicated Dart isolate — never on the UI thread.
- [ ] Log every crash detection event (triggered/cancelled) with full sensor data for calibration. `[AI/ML]`

### BLE mesh

- [ ] Fix the compile error in `mesh_network_service.dart:18` (`invocation_of_non_function_expression`) before any other mesh work. `[CRITICAL]`
- [ ] `listenForSosBeacons()` must be called in a persistent background service — wire it at app init. `[CRITICAL]`
- [ ] BLE scanning must be gated on runtime Bluetooth permission — handle denial gracefully with a clear fallback path.
- [ ] Encrypt every BLE payload with AES-GCM before broadcast — verify decryption on the receiver side in a unit test. `[SECURITY]`
- [ ] BLE mesh is never the only dispatch channel — it supplements SMS and cloud, never replaces them. `[CRITICAL]`
- [ ] Label the BLE feature as "Beta" in the UI until bidirectional communication is verified on two real physical devices.

### AI triage

- [ ] Remove the `Future.delayed()` fake simulation from `AiTriageService` entirely before any other AI work. `[CRITICAL]` `[AI/ML]`
- [ ] Remove `llamadart` from `pubspec.yaml` until on-device LLM is a committed, funded feature. `[AI/ML]`
- [ ] Implement cloud triage first: POST user symptoms + GPS + speed to Gemini Flash API, receive structured JSON. `[AI/ML]`
- [ ] The Gemini prompt must be a system-prompt-level instruction that forces JSON output schema — never parse free text. `[AI/ML]`
- [ ] Implement the TFLite severity classifier (<50 MB) as tier 2 — trained on Indian road accident symptom data. `[AI/ML]` `[INDIA]`
- [ ] Implement the keyword heuristic as tier 3 — a simple map of symptoms to severity, zero external dependencies. `[AI/ML]` `[CRITICAL]`
- [ ] AI triage output must be validated against a typed Dart model class — invalid responses fall to the next tier. `[AI/ML]`
- [ ] Triage advice must be shown in the user's selected language — translate tier 3 heuristic strings via `intl`. `[INDIA]` `[AI/ML]`
- [ ] Never show AI triage as "medical advice" — always append: "For guidance only — call 108 for medical help." `[AI/ML]` `[INDIA]` `[CRITICAL]`

### Location and maps

- [ ] Request Location Always permission — explain why in plain language before the system prompt appears.
- [ ] Fall back to last known location if GPS fix fails — never send a null coordinate to dispatch. `[CRITICAL]`
- [ ] Use MapmyIndia SDK for maps — not raw OSM tiles. MapmyIndia has NLEM (National Emergency Location) POI data. `[INDIA]`
- [ ] Pre-cache map tiles for the user's home district on Wi-Fi at app setup. `[INDIA]`
- [ ] Display the nearest 3 hospitals on the post-SOS screen from the pre-seeded NHM database, not live Overpass. `[INDIA]` `[CRITICAL]`
- [ ] Move the Overpass facility query to a Supabase Edge Function + cron job — never called from the mobile client. `[CRITICAL]`
- [ ] Show GPS accuracy in metres on the SOS confirmation screen — if >100 m, show a warning.

---

## Phase 5 — Security

### Data protection

- [ ] All Supabase tables must have Row Level Security enabled — verify via Supabase dashboard before any launch. `[SECURITY]` `[CRITICAL]`
- [ ] Medical profiles must be encrypted client-side before upload — Supabase should never see plaintext medical data. `[SECURITY]` `[CRITICAL]`
- [ ] Use `flutter_secure_storage` for all keys, tokens, and medical data — not `SharedPreferences`. `[SECURITY]`
- [ ] Implement DPDP Act 2023 consent screen on first launch — explicit opt-in for location and medical data collection. `[SECURITY]` `[INDIA]` `[CRITICAL]`
- [ ] The privacy policy must be available in Hindi and English, accessible from the onboarding screen. `[INDIA]` `[SECURITY]`
- [ ] Implement a "Delete my data" flow — user can wipe all Supabase records from within the app. `[SECURITY]` `[INDIA]`
- [ ] Never log GPS coordinates or medical data to console — add a lint rule to flag any `print()` near location variables. `[SECURITY]` `[CRITICAL]`

### Network and API security

- [ ] All API calls must go over HTTPS — enforce certificate pinning for the Supabase and Twilio endpoints. `[SECURITY]`
- [ ] The Gemini API key must be called server-side via a Supabase Edge Function — never in the Flutter client. `[SECURITY]` `[CRITICAL]`
- [ ] Implement rate limiting on all Edge Functions — max 10 triage requests per user per hour. `[SECURITY]`
- [ ] Validate all API response schemas in Dart before parsing — throw on unexpected fields, never silently ignore. `[SECURITY]`
- [ ] The Supabase anon key gives zero write access without RLS — verify this by attempting an unauthenticated write in a test. `[SECURITY]`

### App hardening

- [ ] Enable ProGuard / R8 obfuscation for all release APK builds. `[SECURITY]`
- [ ] Run a decompilation check (jadx) on the release APK before publishing — verify no secrets are visible. `[SECURITY]` `[CRITICAL]`
- [ ] Disable USB debugging and adb backup in the release manifest. `[SECURITY]`
- [ ] Use Android Play Integrity API to detect compromised devices before processing medical data. `[SECURITY]`
- [ ] Add `FLAG_SECURE` to screens that display medical profiles — prevents screenshots. `[SECURITY]`

---

## Phase 6 — Testing

### Unit tests

- [ ] Every service class must have a corresponding `_test.dart` file with at least 80% branch coverage. `[COLLAB]`
- [ ] `AiTriageService`: test all three tier fallbacks — cloud failure → TFLite → heuristic. `[AI/ML]` `[CRITICAL]`
- [ ] `CrashDetectionService`: test the three-stage gate — a single G-force spike must NOT trigger SOS. `[CRITICAL]`
- [ ] `MeshNetworkService`: test AES-GCM encrypt → decrypt round-trip on every payload type. `[SECURITY]`
- [ ] `EmergencyOrchestrator`: test every state transition with mock services — use Riverpod overrides.
- [ ] Test the PowerSync sync cycle with a mock connector — verify data written offline is synced on reconnect.
- [ ] Test the USSD fallback: verify the correct `tel:` URI is constructed for each Indian emergency number. `[INDIA]`

### Widget and integration tests

- [ ] SOS button widget test: measure time from app launch to button tappable — must be under 1000 ms. `[CRITICAL]`
- [ ] Countdown widget test: verify the cancel button is always visible and cancels dispatch. `[CRITICAL]`
- [ ] Test all 5 regional language strings render without overflow on a 360 dp-wide screen. `[INDIA]`
- [ ] Test the permissions onboarding flow with Location denied — verify the app shows a clear degraded-mode warning.
- [ ] Map widget test: verify pre-cached tiles render with no network connection. `[INDIA]`
- [ ] Run integration tests on a physical budget Android device (Redmi / Realme), not just emulator. `[INDIA]` `[CRITICAL]`

### Field and stress testing

- [ ] Field test on an actual Indian highway — test crash detection, GPS accuracy, and 112 dialling in real conditions. `[INDIA]` `[CRITICAL]`
- [ ] Test with airplane mode on for 10 minutes before SOS — verify the offline queue dispatches correctly on reconnect. `[CRITICAL]`
- [ ] Test with a cracked screen protector on a budget phone — the SOS button must be hittable with one thumb. `[CRITICAL]`
- [ ] Test BLE mesh between two physical devices at 10 m, 20 m, and 30 m — both open area and built-up area.
- [ ] Simulate a 30-minute background run and verify the background service is still alive — measure memory usage.
- [ ] Test with low battery (15%) — verify the app does not kill its background service before a foreground app does.
- [ ] Battery drain test: run the app for 2 hours in background — drain must be under 3% per hour. `[INDIA]`

---

## Phase 7 — UI / UX

### Panic-proof design

- [ ] Home screen: the SOS button must occupy at least 60% of screen height. Nothing else competes for attention. `[CRITICAL]`
- [ ] The SOS button must be operable with one thumb without looking — test with eyes closed. `[CRITICAL]`
- [ ] All tap targets in the emergency flow must be at least 88×88 dp (WCAG 2.5.5 for safety-critical apps). `[CRITICAL]`
- [ ] The countdown cancel button must be the same size as or larger than the SOS button. `[CRITICAL]`
- [ ] No emergency flow screen should require reading more than 6 words to proceed. `[CRITICAL]`
- [ ] Never show a loading spinner in the SOS countdown flow — show progress text instead ("Sending to 112..."). `[CRITICAL]`
- [ ] The app must be fully operable in bright sunlight — test contrast ratios at maximum screen brightness.

### Honest status communication

- [ ] Never show a success screen until the dispatch is confirmed — replace all optimistic UI with real status. `[CRITICAL]`
- [ ] Show a real-time dispatch log: "112 notified ✓", "Cloud sync pending...", "SMS queued" — not a generic spinner. `[CRITICAL]`
- [ ] Show GPS accuracy (e.g. "Location accurate to 15 m") on the SOS screen — low accuracy must trigger a warning.
- [ ] Show which AI triage tier is active: "AI advice (cloud)" or "Offline estimate" — never present them as equivalent. `[AI/ML]`
- [ ] If any dispatch channel fails silently, show a red banner with the specific failure — never hide errors from the user. `[CRITICAL]`

### Accessibility

- [ ] All text must pass WCAG AA contrast ratio (4.5:1 for body, 3:1 for large text) in both light and dark mode.
- [ ] Replace all deprecated `.withOpacity()` with `.withValues(alpha:)` across all 30+ occurrences.
- [ ] Add `Semantics` widget labels to all interactive elements for screen reader support.
- [ ] TTS must read out the triage advice automatically when SOS is active — no user action required. `[INDIA]` `[CRITICAL]`
- [ ] The app must be fully operable without reading — icons must be universally understood or labeled in the user's language. `[INDIA]`

### Localisation

- [ ] All user-facing strings must be in ARB files — zero hardcoded English strings in `.dart` files. `[INDIA]` `[CRITICAL]`
- [ ] Triage advice strings in the heuristic tier must be translated before launch — Hindi at minimum. `[INDIA]` `[CRITICAL]`
- [ ] Test every language string for text overflow on a 360 dp screen — wrap or truncate gracefully. `[INDIA]`
- [ ] Date/time formats must use the locale's convention — Indian users use DD/MM/YYYY, not MM/DD/YYYY. `[INDIA]`
- [ ] TTS locale must switch with the app language — Hindi TTS for Hindi mode, not English synthesis of Hindi words. `[INDIA]`
- [ ] The language selector must be on the onboarding screen — not buried in settings. `[INDIA]`

---

## Phase 8 — Collaboration

### Git and PR discipline

- [ ] Branch naming: `feat/*`, `fix/*`, `chore/*`, `hotfix/*` — enforced via branch protection rules. `[COLLAB]`
- [ ] Commit messages follow Conventional Commits: `feat:`, `fix:`, `chore:`, `docs:`, `test:`, `refactor:`. `[COLLAB]`
- [ ] Every PR must reference a GitHub issue number in the description. `[COLLAB]`
- [ ] PRs must not exceed 400 lines of diff — break larger work into stacked PRs. `[COLLAB]`
- [ ] Every PR must include a "Testing" section: what was tested, on what device, with what result. `[COLLAB]`
- [ ] Reviewers must check: does this PR introduce any `print()` calls, hardcoded strings, or hardcoded secrets? `[COLLAB]` `[SECURITY]`
- [ ] No PR merges on Fridays unless it is a critical hotfix. `[COLLAB]`
- [ ] The PR author resolves merge conflicts — never ask the reviewer to do it. `[COLLAB]`

### Documentation

- [ ] `ARCH.md` must be updated any time a new service is added or a service boundary changes. `[COLLAB]`
- [ ] Every public Dart method must have a `///` dartdoc comment explaining what it does and what can go wrong. `[COLLAB]`
- [ ] The README must have a "Feature status" table: Real / In Progress / Planned / Removed — updated each sprint. `[COLLAB]` `[CRITICAL]`
- [ ] Keep a `CHANGELOG.md` updated with every sprint — used for release notes and investor demos. `[COLLAB]`
- [ ] Document every third-party API limit: Overpass rate limit, Gemini token quota, Twilio free tier caps. `[COLLAB]`
- [ ] Write a `RUNBOOK.md` for production incidents: how to check Supabase health, re-trigger sync, disable BLE. `[COLLAB]`

### Code review standards

- [ ] Reviewer must run the code locally or verify CI passes — no approval without execution. `[COLLAB]`
- [ ] Any change to `EmergencyOrchestrator` requires two reviewers, not one. `[COLLAB]` `[CRITICAL]`
- [ ] Security-sensitive files (auth, encryption, permissions) require a dedicated security review comment. `[COLLAB]` `[SECURITY]`
- [ ] Leave constructive comments — every suggestion must include a "why" and optionally a "how". `[COLLAB]`
- [ ] Approve only when all discussion threads are resolved — do not merge with open unresolved threads. `[COLLAB]`

---

## Phase 9 — Launch

### Pre-launch verification

- [ ] Run `flutter analyze` — zero errors, zero warnings permitted for a release build. `[CRITICAL]`
- [ ] Decompile the release APK with `jadx` — verify no secrets, no debug symbols are visible. `[SECURITY]` `[CRITICAL]`
- [ ] Test the full SOS flow end-to-end on 3 different physical devices at 3 different network conditions. `[CRITICAL]`
- [ ] Verify the DPDP consent flow appears on a fresh install and data can be deleted from within the app. `[INDIA]` `[SECURITY]` `[CRITICAL]`
- [ ] Confirm all Supabase RLS policies are live — test an unauthenticated write attempt and verify it fails. `[SECURITY]` `[CRITICAL]`
- [ ] Verify the 112 India API integration is active and returns a valid response in a staging test. `[INDIA]` `[CRITICAL]`
- [ ] Confirm the NHM hospital database is pre-seeded in the shipped APK and loads with no network. `[INDIA]` `[CRITICAL]`
- [ ] Test the app with a brand-new SIM card (no contacts, no prior sessions) — verify anonymous auth works.

### Store submission

- [ ] Google Play requires written justification for `SEND_SMS` and `ACCESS_BACKGROUND_LOCATION` — prepare this before submission. `[CRITICAL]`
- [ ] Emergency apps require the "Emergency Contacts" declaration in Play Console — complete this form. `[INDIA]`
- [ ] App Store requires HealthKit entitlement if using crash detection — apply for the entitlement before submission.
- [ ] App description must not claim features that are not fully functional in the submitted build. `[CRITICAL]`
- [ ] Include screenshots showing the Hindi UI — Play Store India listing should show regional language. `[INDIA]`

### Monitoring and observability

- [ ] Integrate Sentry or Firebase Crashlytics — every unhandled exception in production must create an alert. `[CRITICAL]`
- [ ] Set up a Supabase dashboard alert if the incidents table receives more than 100 writes in 1 minute (detect spam/abuse). `[SECURITY]`
- [ ] Track AI triage tier distribution (cloud vs TFLite vs heuristic) as a metric — if cloud drops below 90%, investigate. `[AI/ML]`
- [ ] Monitor false-positive crash detection rate — if >5% cancellations per triggers, retune the threshold. `[CRITICAL]` `[INDIA]`
- [ ] Set up uptime monitoring for Supabase Edge Functions with PagerDuty or BetterUptime.
- [ ] Track the dispatch success rate per channel (SMS / Cloud / BLE) as a real-time metric. `[CRITICAL]`

---

## Quick reference — tag legend

| Tag | Meaning |
|-----|---------|
| `[CRITICAL]` | Ignoring this means the app fails, risks lives, or creates legal liability |
| `[COLLAB]` | Required for high-quality multi-contributor development |
| `[INDIA]` | Specific to India's infrastructure, laws, devices, or languages |
| `[AI/ML]` | Governs all decisions around triage, model inference, and AI output |
| `[SECURITY]` | Data protection, secrets management, and privacy compliance |

---

## Quick reference — priority order

```
Phase 5 (Security)       ← before touching any production data
Phase 1 (Planning)       ← before writing any code
Phase 2 (Architecture)   ← before any feature development
Phase 3 (Environment)    ← before the first PR is merged
Phase 4 (Development)    ← ongoing, per-feature
Phase 6 (Testing)        ← gating every PR and every sprint
Phase 7 (UI/UX)          ← gating every UI PR
Phase 8 (Collaboration)  ← enforced from day one via CI
Phase 9 (Launch)         ← every item is a hard gate before release
```

---

*Last updated: April 2026 — update this file after every architecture sync.*
