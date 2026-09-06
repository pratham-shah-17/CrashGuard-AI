import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../logging/app_log.dart';

/// Phase 2 — Predictive SOS preloader.
///
/// Fires when [DrivingModeService] transitions to [DrivingMode.driving].
/// Pre-warms two critical connections so the SOS pipeline is faster
/// when it actually fires:
///
///   1. Supabase Edge Function — a lightweight HEAD request establishes the
///      TCP+TLS session and HTTP/2 connection to the edge region. This
///      eliminates the ~300–600ms cold-handshake overhead on the first
///      real triage call.
///
///   2. GPS — requests a medium-accuracy position to ensure the GNSS chipset
///      is in a warm-start state. The crash detection service already keeps
///      a high-accuracy stream running, so this is a belt-and-suspenders
///      warm-up for the manual-SOS path (phone in pocket while driving).
///
/// Both operations are fully non-blocking and fire-and-forget.
/// Errors are silently ignored — this is a best-effort optimisation, not a
/// critical path. If the pre-warm fails the SOS pipeline is unaffected.
class PredictiveSosPreloader {
  PredictiveSosPreloader._();

  /// Call when driving mode becomes active.
  /// Fire-and-forget — do not await.
  static Future<void> onDrivingModeActivated() async {
    appLog.d('[Preloader] Driving mode activated — pre-warming connections');
    await Future.wait<void>([_prewarmSupabaseEdge(), _prewarmGps()]);
    appLog.d('[Preloader] Pre-warm complete');
  }

  // ── Supabase edge function TLS pre-warm ──────────────────────────────────

  static Future<void> _prewarmSupabaseEdge() async {
    try {
      final url = dotenv.env['SUPABASE_URL']?.trim();
      if (url == null || url.isEmpty) return;

      // HEAD request: establishes TCP + TLS session, receives headers only.
      // No auth needed — unauthenticated HEAD returns 401/405 which is fine;
      // the goal is TLS session establishment, not a valid response.
      await http
          .head(Uri.parse('$url/functions/v1/triage-gemini'))
          .timeout(const Duration(seconds: 4));
      appLog.d('[Preloader] Supabase edge TLS session pre-warmed ✓');
    } on Object catch (_) {
      // Expected on first cold-start or offline — not an error.
      appLog.d('[Preloader] Supabase pre-warm skipped (offline or timeout)');
    }
  }

  // ── GPS chipset warm-up ──────────────────────────────────────────────────

  static Future<void> _prewarmGps() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return;

      // Medium accuracy: fast chipset warm-up without high-power GPS mode.
      // The crash detection service's high-accuracy stream is already running,
      // but on some devices it runs on a separate engine; this ensures the
      // "getCurrentPosition" path used by LocationService is also warm.
      await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 4),
        ),
      );
      appLog.d('[Preloader] GPS chipset pre-warmed ✓');
    } on Object catch (_) {
      appLog.d('[Preloader] GPS pre-warm skipped');
    }
  }
}
