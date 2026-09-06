---
name: roadsos-master-rulebook
description: Applies the RoadSOS Master Development Rulebook (200+ checklist items across 9 phases in docs/DEVELOPMENT_RULEBOOK.md). Use when planning or implementing SOS, emergency dispatch, India compliance (112/108/DPDP), AI triage tiers, BLE mesh, crash detection, Supabase/RLS, localization, security, testing, launch gates, or when the user mentions RoadSOS rulebook, CRITICAL rules, Phase 1–9, or master checklist.
---

# RoadSOS Master Rulebook Skill

## Canonical source

Read **`docs/DEVELOPMENT_RULEBOOK.md`** in `docs/` for the full numbered checklist, tag legend (`[CRITICAL]`, `[COLLAB]`, `[INDIA]`, `[AI/ML]`, `[SECURITY]`), and sprint checkbox updates.

## When to load which phase

| Situation | Read first |
|-----------|------------|
| New feature or scope | Phase 1 Planning + Phase 8 Collaboration |
| Data model, DB, privacy | Phase 2 Architecture + **Phase 5 Security** |
| CI, secrets, formatting | Phase 3 Environment |
| Flutter / services / SOS UI | Phase 4 Development + Phase 7 UI/UX |
| PR or test plan | Phase 6 Testing + Phase 8 Collaboration |
| Release candidate | Phase 9 Launch |

The file’s **“Quick reference — priority order”** overrides casual ordering: treat **Phase 5 (Security)** and **Phase 1 (Planning)** as gates before trusting production data or expanding scope.

## Agent workflow

1. Identify tags relevant to the task (e.g. `[CRITICAL]` + `[INDIA]` for emergency numbers).
2. For each changed area, verify applicable **`[CRITICAL]`** rows in the checklist (dispatch honesty, no simulated-as-real, RLS, structured triage, SOS UX constraints).
3. Prefer referencing phase + tag in PR descriptions (e.g. “Phase 4 dispatch — parallel channels per rulebook”).
4. Delegate deep PR review of `[CRITICAL]` coverage to the **roadsos-critical-reviewer** subagent when appropriate.

## Related Cursor assets

- **Always-on rule**: `.cursor/rules/roadsos-master-rulebook.mdc`
- **Dart**: `.cursor/rules/roadsos-flutter-emergency.mdc`
- **Supabase**: `.cursor/rules/roadsos-supabase-backend.mdc`
