import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'camera_triage_service.dart';

/// In-memory hand-off of the most recently captured crash-scene photo so the
/// auto-SOS pipeline can opportunistically pass it into Gemma 4 27B vision.
///
/// Why this exists:
///   Before this store, `AiTriageService.triageEmergency()` always passed
///   `scenePhoto = null` to the Gemma 4 cloud tier, which meant the documented
///   "Tier 1 — Gemma 4 27B + Vision" pipeline was effectively text-only on the
///   automatic SOS path. The vision capability shipped in the bystander
///   workflow only — which is the wrong-shaped surface for a victim who is
///   alone or unconscious.
///
/// How it gets populated:
///   * IncidentReportingScreen.captureScene() pushes the captured
///     [CapturedScenePhoto] here immediately after camera roll.
///   * BystanderCoachScreen / dashboard "Capture Scene" do the same.
///
/// Freshness:
///   A photo older than [_maxAgeSeconds] (default 120s) is considered stale
///   and is NOT used by triage — old crash photos must not contaminate a
///   later, unrelated SOS. The store is also cleared after a successful SOS
///   so the next incident gets a clean slate.
class LastScenePhotoStore {
  LastScenePhotoStore();

  static const int _maxAgeSeconds = 120;

  CapturedScenePhoto? _last;

  /// Store a photo. Replaces any previous one.
  void store(CapturedScenePhoto photo) {
    _last = photo;
  }

  /// Returns the most recently captured photo if it is still fresh.
  /// Returns null otherwise so triage callers can skip the vision tier.
  CapturedScenePhoto? takeIfFresh() {
    final p = _last;
    if (p == null) return null;
    final ageSec = DateTime.now().toUtc().difference(p.capturedAt).inSeconds;
    if (ageSec > _maxAgeSeconds) return null;
    return p;
  }

  /// Drop the stored photo (called after SOS completes).
  void clear() {
    _last = null;
  }
}

final lastScenePhotoStoreProvider = Provider<LastScenePhotoStore>((ref) {
  return LastScenePhotoStore();
});
