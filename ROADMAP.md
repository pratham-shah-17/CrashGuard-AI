# Roadmap

This roadmap is grounded in work already in flight (open PRs, `docs/BLUEPRINT_GAP_ANALYSIS.md`)
rather than aspirational features — see [Discussions](https://github.com/pratham-shah-17/CrashGuard-AI/discussions)
to propose new ones.

## Now — v1.0.x hardening

- [ ] Land the highest-value backlog PRs and close the rest as duplicates (in progress)
- [ ] Debounce Nominatim autocomplete in Safe Walk ([#281](https://github.com/pratham-shah-17/CrashGuard-AI/pull/281))
- [ ] `AppLocaleController` unit test coverage ([#77](https://github.com/pratham-shah-17/CrashGuard-AI/pull/77))
- [ ] Fix insecure CORS `Origin: null` fallback in `family-track` edge function ([#78](https://github.com/pratham-shah-17/CrashGuard-AI/pull/78))
- [ ] Set up code coverage reporting so a coverage badge reflects real numbers, not a placeholder

## Next — v1.1

- [ ] Vehicle rescue module + expanded multi-language localization ([#71](https://github.com/pratham-shah-17/CrashGuard-AI/pull/71))
- [ ] Scene intelligence — AI crash-scene analyzer via Gemini Vision ([#103](https://github.com/pratham-shah-17/CrashGuard-AI/pull/103))
- [ ] Family Circle live incident links / iOS glass-UI polish ([#121](https://github.com/pratham-shah-17/CrashGuard-AI/pull/121))
- [ ] E2E test suite on real devices (currently unit/widget tests only — see `docs/BLUEPRINT_GAP_ANALYSIS.md`)

## Later — exploratory

- [ ] Case-study demo video (script exists in `docs/VIDEO_SCRIPT.md`, production pending)
- [ ] Published benchmarks (AI response latency, offline cold-start, BLE mesh range/latency, APK size)
- [ ] Deployment guide for state EMS / government adoption (referenced in README, needs a standalone doc)

## Won't do (for now)

- Anything that requires the AI triage app server or cloud model to be a hard dependency for the emergency SOS path — offline reliability is non-negotiable for this project.

---

Want to help with any of these? Check [`CONTRIBUTING.md`](CONTRIBUTING.md) and look for issues labeled
[`good first issue`](https://github.com/pratham-shah-17/CrashGuard-AI/labels/good%20first%20issue).
