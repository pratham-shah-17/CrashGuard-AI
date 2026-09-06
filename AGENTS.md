# AGENTS.md

## Cursor Cloud specific instructions

### Project overview

CrashGuard AI is a Flutter mobile app (Dart) with Supabase Edge Functions (TypeScript/Deno) as the backend. The primary development loop is Flutter-based: `flutter pub get`, `dart analyze`, `flutter test`, `flutter build web`.

### Flutter SDK

The CI pins **Flutter 3.41.9** (Dart 3.11.5). The `pubspec.yaml` SDK constraint is `^3.11.0`. Flutter must be installed at `/opt/flutter` with `/opt/flutter/bin` on `PATH` (the update script handles this).

### Key commands

| Action | Command |
|---|---|
| Install deps | `flutter pub get` |
| Lint | `dart analyze` |
| Test | `flutter test` |
| Build web | `flutter build web --dart-define=SUPABASE_URL="$SUPABASE_URL" --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"` |
| Serve demo | `python3 -m http.server 8080` (from repo root, then visit `/demo/index.html`) |
| Serve Flutter web | `cd build/web && python3 -m http.server 8081` |

### Environment file

Copy `assets/env.template` to `assets/.env` before running the Flutter app. The app needs `SUPABASE_URL` and `SUPABASE_ANON_KEY` to initialize — without them the Flutter web app shows a blank page. The standalone demo at `demo/index.html` works without any env vars.

### Testing without external services

- `dart analyze` and `flutter test` work without any secrets or external services.
- The standalone HTML demo (`demo/index.html`) supports an **Offline Fallback** triage mode that runs keyword-based classification without a Google AI API key.
- The full Flutter web app requires Supabase credentials to initialize (see below).

### Building and serving the Flutter web app

The web build is a **release build** by default, so `.env` files are not loaded. Pass secrets via `--dart-define`:

```bash
flutter build web \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"
```

Serve from the build output directory directly (not the repo root), so relative asset paths resolve:

```bash
cd build/web && python3 -m http.server 8081
```

Serving from the repo root (e.g. `http://localhost:8080/build/web/`) will cause 404s for `flutter_bootstrap.js` and `manifest.json`.

### Gotchas

- The `flutter_blue_plus_winrt` warnings during `pub get` / build are harmless (Windows-only plugin, irrelevant on Linux).
- Localization warnings about untranslated messages in `bn`, `hi`, `mr`, `ta`, `te` are expected and non-blocking.
- The Wasm dry-run warnings during `flutter build web` are informational only; the JS build succeeds.
- `assets/.env` is not gitignored at the `assets/` path (only `/.env` at root is ignored); do not commit it with secrets.

### Supabase Edge Functions

Located in `supabase/functions/`. Deploying requires the Supabase CLI and project credentials. Not required for running tests or the standalone demo.
