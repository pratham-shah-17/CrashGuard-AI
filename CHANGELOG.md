# Changelog

All notable changes to CrashGuard AI are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this project is
pre-1.0-stable and does not yet follow strict SemVer between minor versions.

## [Unreleased]

- Repository-health pass: closed ~114 duplicate automated PRs, pruned ~160
  dead branches, added community-health files, architecture diagrams, and
  a real threat model to `SECURITY.md`.

## [1.0.0] — 2026-08-03

First tagged release.

### Highlights

- Offline-first crash detection (accelerometer + GPS fusion) with automatic SOS
- 4-tier Gemma 4 triage: cloud vision (27B) → on-device (E4B) → weighted
  heuristic → keyword fallback, degrading gracefully with no connectivity
- Server-side SMS dispatch to 108/112 via Twilio (no credentials on-device)
- BLE mesh beacon (AES-GCM encrypted) for nearby bystander alerting
- Voice-guided first aid in 6 Indian languages (English, Hindi, Bengali,
  Marathi, Tamil, Telugu)
- Offline regional facility/trauma-center lookup via PowerSync

### Known limitations

See [`docs/BLUEPRINT_GAP_ANALYSIS.md`](docs/BLUEPRINT_GAP_ANALYSIS.md) for the
full honest status table. Notable gaps at this release:

- Sub-100ms SOS path is not yet benchmarked in CI
- Crash detection has no microphone signal or per-device calibration UI
- Live contact SMS verification (OTP) not implemented
- Full E2E test suite runs on unit/widget tests only — no on-device E2E in CI
- Only 6 of a planned 12 Indian languages are localized
