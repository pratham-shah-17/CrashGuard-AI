# Release checklist — CrashGuard AI

Use before **store submission**, **major demo**, or **production Supabase** cutover.

## Code & build

- [ ] `dart analyze` clean (or tracked suppressions only).
- [ ] `flutter test` green locally and in CI.
- [ ] Version bumped in `pubspec.yaml` if shipping a tagged build.
- [ ] Android: release APK/AAB signed; obfuscation maps archived (`--split-debug-info`).

## Supabase

- [ ] All migrations applied to target project (`supabase db push` or CI migration pipeline).
- [ ] Secrets set: `GEMMA_API_KEY`, Twilio (if SMS), Overpass/cron env for `sync-osm-facilities`.
- [ ] RLS verified on every table with client access (`docs/RLS_AND_SECURITY.md`).
- [ ] Retention policy aligned (`incident_retention` migration + product policy).

## Client configuration

- [ ] `SUPABASE_URL`, `SUPABASE_ANON_KEY` via `--dart-define` or secure CI secrets — not hardcoded.
- [ ] `SMS_DISPATCH_URL` points to deployed `sms-dispatch` if using automated SMS.
- [ ] PowerSync URL matches environment.

## Demo / judges

- [ ] `docs/JUDGE_DEMO_SCRIPT.md` dry-run on a **physical Android** device.
- [ ] Offline path recorded (airplane mode) if claiming resilience.
- [ ] `docs/PLATFORM_MATRIX.md` reviewed — claims match platform.

## Legal / product

- [ ] Privacy policy assets current (`assets/legal/`).
- [ ] Medical / emergency disclaimer visible where required.
