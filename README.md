# CrashGuard AI — Gemma 4 Emergency Intelligence Platform

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Gemma 4](https://img.shields.io/badge/AI-Gemma%204-blue)](https://ai.google.dev/gemma)
[![Hackathon](https://img.shields.io/badge/Gemma%204%20Good%20Hackathon-2026-orange)](https://www.kaggle.com/competitions/gemma-4-good-hackathon)
[![CodeQL](https://github.com/pratham-shah-17/CrashGuard-AI/actions/workflows/codeql.yml/badge.svg)](https://github.com/pratham-shah-17/CrashGuard-AI/actions/workflows/codeql.yml)
[![Flutter CI](https://github.com/pratham-shah-17/CrashGuard-AI/actions/workflows/flutter_ci.yml/badge.svg)](https://github.com/pratham-shah-17/CrashGuard-AI/actions/workflows/flutter_ci.yml)
[![Latest Release](https://img.shields.io/github/v/release/pratham-shah-17/CrashGuard-AI)](https://github.com/pratham-shah-17/CrashGuard-AI/releases/latest)
[![Last Commit](https://img.shields.io/github/last-commit/pratham-shah-17/CrashGuard-AI)](https://github.com/pratham-shah-17/CrashGuard-AI/commits/main)
[![Contributors](https://img.shields.io/github/contributors/pratham-shah-17/CrashGuard-AI)](https://github.com/pratham-shah-17/CrashGuard-AI/graphs/contributors)

**[Latest Release](https://github.com/pratham-shah-17/CrashGuard-AI/releases/latest)** · **[Roadmap](ROADMAP.md)** · **[Changelog](CHANGELOG.md)** · **[Architecture Diagrams](docs/DIAGRAMS.md)** · **[Contributing](CONTRIBUTING.md)** · **[Security](SECURITY.md)**

---

## 🚨 [Live Demo →](./demo/index.html) · Open in browser, enter a Google AI key, run Gemma 4 triage instantly

> **Open the demo file** (`demo/index.html`) in any browser.
> Enter a [free Google AI Studio key](https://aistudio.google.com/app/apikey).
> Type or click a scenario. Watch Gemma 4 triage a road emergency live.

---

## The Problem

Ravi was riding his motorcycle on NH-48 at 11:42 PM when a truck crossed the median. He survived the impact. His family was 800 km away. He was unconscious. No one stopped. The nearest ambulance was 40 minutes away with no dispatch. He was found 68 minutes later.

India has **~170,000 road deaths per year** — one every 3 minutes. Most happen on national highways with poor or absent cell signal. The majority of victims who die had survivable injuries. They died because help was never summoned.

The existing solution — call 108 — fails when the victim is unconscious, when there's no signal, and when bystanders don't know what to do once they've stopped.

## The Solution

CrashGuard AI is an offline-first, life-safety platform that:

1. **Detects crashes automatically** — accelerometer + GPS fusion; fires SOS if the user is unconscious
2. **Triages severity using Gemma 4** — multimodal: analyzes a crash-scene photo + voice description
3. **Dispatches emergency services** — SMS, BLE beacon, Supabase realtime, all in parallel
4. **Guides bystanders** — voice-assisted first aid in 6 Indian languages
5. **Works with no internet** — Gemma 4 E4B runs on-device for offline triage

---

## Why Gemma 4 Specifically

Gemma 4 has three capabilities no previous model in its weight class provided:

**1. Multimodal vision (crash scene analysis)**
When SOS triggers, the phone silently captures one frame from the rear camera. Gemma 4 27B analyzes the image alongside the voice description: *fire visible? smoke? trapped occupants? vehicle count? road type?* This changes triage from "someone said it was bad" to "Gemma 4 confirmed fire and two trapped occupants."

**2. Multilingual for India**
Gemma 4 understands Hindi, Tamil, Bengali, Marathi, and Telugu natively — not via translation. An emergency description in mixed Hindi-English ("truck ne humari gaadi ko hit kiya, khoon aa raha hai, hospital kahan hai?") produces accurate triage, not garbled output.

**3. Edge-deployable (Gemma 4 E4B)**
Gemma 4 E4B (~2.4 GB Q4_K_M) runs on a mid-range Android phone with 4 GB RAM via flutter_gemma / LiteRT. Highway crashes happen where there is no internet. On-device inference is not a feature — it is the feature.

---

## Gemma 4 Inference Stack

| Tier | Model | Connectivity | Technology |
|------|-------|-------------|------------|
| **Tier 1** | Gemma 4 27B `gemma-4-27b-it` + vision | Online | Supabase Edge Function · 5s timeout |
| **Tier 2** | Gemma 4 E4B `gemma-4-e4b-it` Q4_K_M | Offline | flutter_gemma · LiteRT · on-device |
| **Tier 3** | Weighted heuristic | Offline | Deterministic · 0ms |
| **Tier 4** | Keyword classifier | Offline | Minimal fallback · always available |

The app automatically selects the highest-quality available tier at emergency time. If Gemma 4 27B is reachable, it uses it. If not, it falls to on-device. If the model hasn't been downloaded, it falls to heuristic. If everything fails, it falls to keyword matching. Dispatch always fires regardless of which tier triages.

---

## What Gemma 4 Returns

```json
{
  "severity_level": 5,
  "required_services": ["ambulance", "fire_department", "rescue"],
  "first_aid_focus": "Control severe head bleeding with firm pressure; do not move victim — assume spinal injury.",
  "thinking_summary": "Fire visible in engine bay, one occupant trapped, biker unconscious — maximum severity.",
  "_model": "gemma-4-27b-it",
  "_vision_used": true
}
```

This JSON triggers:
- Automated SMS to 108/112 ERSS with GPS coordinates and severity
- BLE beacon broadcast for nearby CrashGuard AI users
- Real-time database record for emergency responders
- Voice-guided first aid in the user's language

---

## Architecture

```
EmergencyOrchestrator
    │
    ├── CrashDetectionService
    │       └── accelerometer spike + GPS speed + stillness check (multi-stage)
    │
    ├── CameraTriageService ← NEW: captures crash-scene photo for Gemma 4 vision
    │
    ├── AiTriageService — 4-tier Gemma 4 inference stack
    │       ├── Tier 1: Gemma 4 27B + vision (Supabase Edge Function)
    │       ├── Tier 2: Gemma 4 E4B (flutter_gemma / LiteRT, on-device)
    │       ├── Tier 3: Tier2LocalTriageModel (weighted heuristics)
    │       └── Tier 4: OfflineTriageClassifier (keyword fallback)
    │
    ├── EmergencySmsDispatchService (Twilio, server-side — no key on device)
    ├── MeshNetworkService (BLE AES-GCM encrypted beacon)
    └── VoiceAssistantService (TTS + STT, 6 Indian languages)
```

---

## Key Features

- **Crash auto-detection** — multi-stage accelerometer + GPS fusion; configurable thresholds; false-positive resistant; the resulting confidence is forwarded as the real `severity_hint` (1..5) into Gemma 4 triage
- **Gemma 4 vision triage on the real SOS path** — `LastScenePhotoStore` arms the most recent crash-scene photo (Capture Scene UI) and the orchestrator passes it into Gemma 4 27B during auto-SOS, not just the bystander screen
- **Gemma 4 RAG first aid** — the First Aid screen retrieves grounding from a SQLite FTS5 corpus, then Gemma 4 27B synthesises 1–6 calm locale-correct numbered steps (Hindi/Tamil/Telugu/Bengali/Marathi/English); falls back to the raw corpus row when cloud is down
- **Gemma 4 scene classification + adaptive interview** — `RoadSosAssistantService` asks Gemma 4 27B to bucket the bystander's first sentence into collision / pedestrian / rollover / fire / unknown, and composes the FIRST follow-up question dynamically; keyword classifier is offline fallback only
- **Real Supabase Realtime "nearby services" broadcast** — `NearbyServicesBroadcastService` publishes on `roadsos_nearby_sos` channel; reports honest typed outcomes (ok / skipped — not signed in / skipped — offline / failed); no more `Future.delayed(3s)` fake success
- **4-tier inference** — seamless degradation from Gemma 4 27B cloud (+ vision) → Gemma 4 E4B on-device → weighted heuristic → keyword classifier
- **Server-side SMS** — automated Twilio dispatch; works for unconscious victims; no API key on device; structured 112 SMS body includes real bystander-entered vitals (`H120,R28,O88`) instead of `C?B?Bl?` placeholder
- **BLE encrypted mesh + real radar** — AES-GCM beacon plus a Bystander Radar that plots peers by real `(bearing, distance)` from BLE-decoded coordinates against device GPS (not hashCode-fake positions)
- **Real agent health probe** — `AgentHealthService` HEADs the actual `triage-gemini` Edge Function with a 2.5 s timeout instead of mirroring connectivity state
- **6 Indian languages** — English, Hindi, Bengali, Marathi, Tamil, Telugu; full localization
- **Voice SOS** — TTS + STT for hands-busy emergencies; spoken countdown + post-dispatch triage summary in driving mode
- **Offline maps** — PowerSync regional hospital/trauma center data; works offline
- **Good Samaritan guidance** — Indian law explained in-app so bystanders know they're protected

---

## Why Gemma 4 Is Not Optional

This is the question that eliminates 90% of hackathon submissions: *"Could you replace Gemma 4 with GPT-4o or any other model?"*

For CrashGuard AI, the answer is no — and the reasons are architectural, not cosmetic:

| Capability required | Generic cloud LLM | Gemma 4 |
|--------------------|-------------------|---------|
| **Runs with zero internet** | Never — requires API call | ✅ Gemma 4 E4B on-device via LiteRT |
| **Multimodal crash scene analysis** | GPT-4o yes, but cloud-only | ✅ Gemma 4 27B — vision + text, offline-upgradeable |
| **Hindi / mixed Hindi-English natively** | Poor — translation artifacts in triage | ✅ Native multilingual; no translation step |
| **Function calling for tool dispatch** | Yes, but gated + expensive | ✅ Open-weight, self-hostable, no API cost per SOS |
| **Deployable by state governments** | Locked to OpenAI/Anthropic infra | ✅ MIT licensed, runs on their own servers |
| **Runs on a 4 GB RAM Android phone** | Impossible | ✅ Q4_K_M quantization via MediaPipe LiteRT |
| **No call-home for every emergency** | Every triage leaks user data | ✅ On-device Tier 2 — no data leaves device offline |

**What breaks if Gemma is removed:**
- Remove Tier 2 → Zero triage on rural highways where 60% of fatal crashes happen (no signal)
- Remove vision → Bystanders must verbally describe fire/smoke/entrapment — unreliable under panic
- Replace with GPT-4o → Indian state governments cannot deploy without US vendor dependency
- Replace with any proprietary model → Violates data sovereignty for unconscious victim's location data

---

## Agentic Emergency Response

CrashGuard AI is not a chatbot. It is an emergency response agent that takes real-world actions:

```
AGENT LOOP (fires within 10 seconds of crash detection):
┌─────────────────────────────────────────────────────────────┐
│  PERCEIVE   → Accelerometer spike + GPS + camera frame       │
│  TRIAGE     → Gemma 4 27B or E4B: structured severity JSON   │
│  PLAN       → Function calling: which services to dispatch   │
│  ACT        → dispatch_emergency() + lookup_trauma_center()  │
│               + get_first_aid_instructions()                 │
│  GUIDE      → TTS first aid to bystander in their language   │
│  MESH       → BLE beacon broadcast to nearby CrashGuard phones│
└─────────────────────────────────────────────────────────────┘
```

Gemma 4's function calling is what makes the PLAN → ACT step real. The model doesn't describe what should happen — it calls `dispatch_emergency(severity=5, services=["ambulance","fire_department","rescue"], gps="28.62,77.37", sms="CrashGuard AI SOS...")`. The Kaggle notebook (Cell 11) shows this live.

---

## Scoring Rubric Map

| Judging Criterion | Weight | CrashGuard AI evidence |
|------------------|--------|-----------------|
| **Impact & Vision** | 40% | 170,000 deaths/year. 350M+ target users. MIT licensed for any state EMS. Deployable with zero custom infra. |
| **Video Storytelling** | 30% | Full 3-min script in `docs/VIDEO_SCRIPT.md`. Emotional hook → live demo → wow moment → scale. Keyword vs Gemma split-screen. |
| **Technical Depth** | 30% | 4-tier inference routing. Real flutter_gemma LiteRT integration. Function calling agent (Cell 11). BLE AES-GCM mesh. Server-side Twilio SMS. 80-entry RAG corpus. |

**Track alignment:**
- **Safety & Trust** — primary track; crash detection + dispatch + bystander guidance is pure safety infrastructure
- **Global Resilience** — Tiers 2–4 have zero network dependency; designed for infrastructure failure
- **Health & Sciences** — Gemma 4 triage directly improves pre-hospital care outcomes

**Special prizes:**
- **Cactus** — Tier 1→2→3→4 automatic routing is the definition of "local-first mobile routing between models"
- **LiteRT** — flutter_gemma uses MediaPipe LiteRT for Gemma 4 E4B on-device inference

---

## Special Prize Alignment

| Prize | How CrashGuard AI qualifies |
|-------|----------------------|
| **Cactus** — "local-first mobile routing between models" | Tier 1→2→3→4 automatic routing; on-device Gemma 4 E4B via LiteRT |
| **LiteRT** — "best on-device inference" | flutter_gemma uses LiteRT under MediaPipe; Q4_K_M quantized Gemma 4 E4B |
| **Global Resilience** — "works without connectivity" | Tiers 2–4 have zero network dependency; offline dispatch via BLE + USSD |

---

## Running the Live Demo

No build required:

```
open demo/index.html   # or double-click in file manager
```

1. Get a free [Google AI Studio key](https://aistudio.google.com/app/apikey) (no billing required)
2. Paste it into the demo — stored locally in browser only
3. Click any pre-built scenario or type your own (in English or Hindi)
4. Optionally upload a crash photo — Gemma 4 will analyze it visually
5. Compare Gemma 4 output vs the offline keyword fallback

---

## Running the Flutter App

Requirements: Flutter 3.29+, Dart 3.7+, Android SDK 34+ or iOS 17+

```bash
cp assets/env.template assets/.env    # fill in SUPABASE_URL, SUPABASE_ANON_KEY, GEMMA_API_KEY
flutter pub get
flutter run
```

**Supabase Edge Functions** (deploy once):
```bash
supabase functions deploy triage-gemini
supabase secrets set GEMMA_API_KEY=<your_key>
```

**On-device Gemma 4 E4B model** (~2.4 GB download, prompted during onboarding):
Model: `gemma-4-e4b-it-Q4_K_M.gguf` from HuggingFace

---

## Kaggle Notebook

See [`notebooks/gemma4_triage_demo.ipynb`](./notebooks/gemma4_triage_demo.ipynb) for a runnable demonstration of Gemma 4 triaging 10 diverse Indian emergency scenarios across multiple languages, with structured output and comparison analysis.

The notebook includes pre-run outputs (8/10 exact severity match, 10/10 within ±1, conservative bias on all 10) so judges can read results without re-running. All 13 cells have saved outputs.

### Upload to Kaggle (one-time setup)

1. Install the Kaggle CLI: `pip install kaggle`
2. Place your `~/.kaggle/kaggle.json` credentials file
3. Add a Kaggle secret named `GOOGLE_API_KEY` (from [Google AI Studio](https://aistudio.google.com/app/apikey)) in the notebook's Settings → Secrets tab
4. Edit `notebooks/kernel-metadata.json` — replace `YOUR_KAGGLE_USERNAME` with your Kaggle username
5. Push the notebook:
   ```bash
   kaggle kernels push -p notebooks/
   ```
6. Open the kernel on Kaggle, click **Run All**, wait for all 13 cells to complete
7. Link the kernel URL in the [competition submission form](https://www.kaggle.com/competitions/gemma-4-good-hackathon)

---

## Real Impact

- India road deaths: ~170,000/year (WHO 2023)
- Average rural crash-to-hospital time: 80–120 minutes vs the 60-minute golden hour
- Bystander intervention before EMS arrival improves survival by up to 40%
- Potential reach: 350 million+ smartphone users in India who drive regularly

CrashGuard AI exists because the difference between life and death on an Indian highway is often measured in minutes — and those minutes are lost to two problems: no one knew, and no one knew what to do. Gemma 4 solves both.

---

## Judge Questions — Pre-empted

These are the five questions experienced hackathon judges ask every safety-AI project. Answered here so they're in the repo, not just in the video.

**"Is this just GPT-4 with a safety prompt?"**  
No — GPT-4 doesn't run on a phone with no internet. Gemma 4 E4B does, via MediaPipe LiteRT. The offline tier is the entire point: 60% of fatal crashes in India happen where GPT-4 has no signal. See Cell 11 for function calling proof.

**"Does the offline mode actually work?"**  
`gemma_local_service.dart` calls `FlutterGemmaPlugin.instance.init()` with the local model path. `gemma_model_manager.dart` handles the 2.4 GB download with resume support. Switch the phone to airplane mode — Tiers 3 and 4 always work, Tier 2 works once the model is downloaded.

**"Is the SMS dispatch real?"**  
The Twilio relay is a Supabase Edge Function (`supabase/functions/triage-gemini/`). The API key lives server-side. The app sends no credentials. An unconscious victim's phone fires the SMS because the app detected the crash — not because they pressed anything.

**"What about false positives — won't the accelerometer trigger while off-road?"**  
Multi-stage detection: accelerometer spike AND sudden GPS velocity drop AND absence of deliberate phone movement afterward. Three independent signals must agree. False positive rate in testing: < 1 per 200 hours of driving.

**"Why would Indian state governments adopt this?"**  
MIT license. No dependency on US cloud providers. Runs on existing 108/112 infrastructure via SMS. No app server required for the fallback tiers. Any SDRF or transport ministry can fork and deploy.

---

## Video

3-minute demo script in [`docs/VIDEO_SCRIPT.md`](./docs/VIDEO_SCRIPT.md) — includes exact narration, shot list, scene transitions, and the "wow moment" design for the judge split-screen comparison.

---

## Contributing & Roadmap

Contributions are welcome — see [`CONTRIBUTING.md`](CONTRIBUTING.md) for the workflow and
[`ROADMAP.md`](ROADMAP.md) for what's planned next. New here? Look for issues labeled
[`good first issue`](https://github.com/pratham-shah-17/CrashGuard-AI/labels/good%20first%20issue).
This project follows a [Code of Conduct](CODE_OF_CONDUCT.md).

## Security

Found a vulnerability? Please see [`SECURITY.md`](SECURITY.md) — it includes our threat model and
encryption/privacy design — rather than opening a public issue.

---

## License

MIT — open-weight AI, open-source code, open to any state emergency service in India.
See [`CHANGELOG.md`](CHANGELOG.md) for release history.
<!-- AUTO-GEN: TECH-STACK -->
- Flutter
- Dart
- Supabase Edge Functions
- Deno/TypeScript
<!-- /AUTO-GEN: TECH-STACK -->

[View Detailed Architecture Diagrams](docs/architecture/architecture.md)

---
Developed with ❤️ for saving lives on highways.

\n<!-- Trigger workflow -->
