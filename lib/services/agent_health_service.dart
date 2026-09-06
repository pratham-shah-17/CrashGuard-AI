import 'dart:async';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';

import '../logging/app_log.dart';
import 'connectivity_service.dart';
import 'gemma_local_service.dart';

/// Phase 4 — Agent health check service.
///
/// Performs a non-blocking readiness probe of the five dispatch agents
/// and reports their status as [AgentHealthSnapshot]. Used by the status
/// indicator to show users whether the system is ready before a crash
/// happens, not after.
///
/// Health levels:
///   [AgentReadiness.ready]       — fully operational
///   [AgentReadiness.degraded]    — functional with reduced capability
///   [AgentReadiness.unavailable] — offline or permission denied
///
/// Probes are designed to be cheap (< 20ms each) and safe to call frequently.
enum AgentReadiness { ready, degraded, unavailable }

class AgentHealthSnapshot {
  final AgentReadiness gemmaCloud;
  final AgentReadiness gemmaOnDevice;
  final AgentReadiness gps;
  final AgentReadiness sms;
  final AgentReadiness ble;
  final DateTime checkedAt;

  const AgentHealthSnapshot({
    required this.gemmaCloud,
    required this.gemmaOnDevice,
    required this.gps,
    required this.sms,
    required this.ble,
    required this.checkedAt,
  });

  /// True if GPS is reachable — minimum requirement for location-based SOS.
  bool get canDispatch => gps != AgentReadiness.unavailable;

  /// True if at least one AI inference tier is ready.
  bool get hasAiCapability =>
      gemmaCloud != AgentReadiness.unavailable ||
      gemmaOnDevice != AgentReadiness.unavailable;

  /// Overall system readiness for a one-line UI label.
  String get summaryLabel {
    if (canDispatch && hasAiCapability) return 'All systems ready';
    if (canDispatch) return 'Ready — AI offline (heuristic fallback)';
    return 'GPS unavailable — check location permission';
  }

  AgentHealthSnapshot copyWith({
    AgentReadiness? gemmaCloud,
    AgentReadiness? gemmaOnDevice,
    AgentReadiness? gps,
    AgentReadiness? sms,
    AgentReadiness? ble,
  }) => AgentHealthSnapshot(
    gemmaCloud: gemmaCloud ?? this.gemmaCloud,
    gemmaOnDevice: gemmaOnDevice ?? this.gemmaOnDevice,
    gps: gps ?? this.gps,
    sms: sms ?? this.sms,
    ble: ble ?? this.ble,
    checkedAt: DateTime.now(),
  );
}

class AgentHealthService {
  final Ref _ref;
  Timer? _pollTimer;
  AgentHealthSnapshot _last = AgentHealthSnapshot(
    gemmaCloud: AgentReadiness.degraded,
    gemmaOnDevice: AgentReadiness.unavailable,
    gps: AgentReadiness.degraded,
    sms: AgentReadiness.degraded,
    ble: AgentReadiness.degraded,
    checkedAt: DateTime(2000),
  );

  final _controller = StreamController<AgentHealthSnapshot>.broadcast();

  AgentHealthService(this._ref);

  AgentHealthSnapshot get current => _last;
  Stream<AgentHealthSnapshot> get stream => _controller.stream;

  void startPolling({Duration interval = const Duration(seconds: 30)}) {
    _pollTimer?.cancel();
    unawaited(check());
    _pollTimer = Timer.periodic(interval, (_) => unawaited(check()));
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<AgentHealthSnapshot> check() async {
    final results = await Future.wait<AgentReadiness>([
      _checkGemmaCloud(),
      _checkGemmaOnDevice(),
      _checkGps(),
      _checkSms(),
      _checkBle(),
    ]);

    _last = AgentHealthSnapshot(
      gemmaCloud: results[0],
      gemmaOnDevice: results[1],
      gps: results[2],
      sms: results[3],
      ble: results[4],
      checkedAt: DateTime.now(),
    );

    appLog.d(
      '[HealthCheck] cloud=${_last.gemmaCloud.name} '
      'onDevice=${_last.gemmaOnDevice.name} '
      'gps=${_last.gps.name} '
      'sms=${_last.sms.name} '
      'ble=${_last.ble.name}',
    );

    if (!_controller.isClosed) _controller.add(_last);
    return _last;
  }

  /// Cached probe result so we do not hammer the Edge Function on every poll.
  AgentReadiness? _gemmaCloudCached;
  DateTime _gemmaCloudCachedAt = DateTime(2000);

  /// Real probe of the Gemma 4 cloud triage tier — issues a tiny HEAD/OPTIONS
  /// request to the Supabase Edge Function. Connectivity is a necessary but
  /// NOT sufficient signal: the device can be on Wi-Fi while the Edge
  /// Function is down or `SUPABASE_URL` is unconfigured.
  ///
  /// Behaviour:
  ///   - `NetworkQuality.none` → `unavailable` (short-circuit, no HTTP)
  ///   - Missing `SUPABASE_URL` → `degraded` (on-device tier still works)
  ///   - 200/204/401/405 on functions endpoint → `ready` (server alive)
  ///   - 5xx or timeout (>2.5s) → `degraded`
  ///   - Network error → `degraded`
  ///
  /// Cached for 25s to bound traffic from the 30s poller.
  Future<AgentReadiness> _checkGemmaCloud() async {
    final connectivity = _ref.read(connectivityServiceProvider);
    if (connectivity.currentQuality == NetworkQuality.none) {
      _gemmaCloudCached = AgentReadiness.unavailable;
      _gemmaCloudCachedAt = DateTime.now();
      return AgentReadiness.unavailable;
    }

    final cached = _gemmaCloudCached;
    if (cached != null &&
        DateTime.now().difference(_gemmaCloudCachedAt).inSeconds < 25) {
      return cached;
    }

    final supabaseUrl = dotenv.env['SUPABASE_URL']?.trim() ?? '';
    if (supabaseUrl.isEmpty) {
      _gemmaCloudCached = AgentReadiness.degraded;
      _gemmaCloudCachedAt = DateTime.now();
      return AgentReadiness.degraded;
    }

    final probeUri = Uri.parse(
      supabaseUrl.endsWith('/')
          ? '${supabaseUrl}functions/v1/triage-gemini'
          : '$supabaseUrl/functions/v1/triage-gemini',
    );

    try {
      // OPTIONS is the lightest call that confirms the function exists.
      // Returns 200/204 if the function is deployed; 404 if missing.
      final response = await http
          .head(probeUri)
          .timeout(const Duration(milliseconds: 2500));
      final code = response.statusCode;
      // 200/204 = OK, 401/405 = server alive but method/auth gating expected
      final ready = code == 200 || code == 204 || code == 401 || code == 405;
      final result = ready ? AgentReadiness.ready : AgentReadiness.degraded;
      _gemmaCloudCached = result;
      _gemmaCloudCachedAt = DateTime.now();
      return result;
    } on Object catch (e) {
      appLog.d('[HealthCheck] Gemma cloud probe failed: $e');
      _gemmaCloudCached = AgentReadiness.degraded;
      _gemmaCloudCachedAt = DateTime.now();
      return AgentReadiness.degraded;
    }
  }

  Future<AgentReadiness> _checkGemmaOnDevice() async {
    final gemma = _ref.read(gemmaLocalServiceProvider);
    if (gemma.isAvailable) return AgentReadiness.ready;
    if (gemma.isInitialized) return AgentReadiness.unavailable;
    return AgentReadiness.degraded; // still loading
  }

  Future<AgentReadiness> _checkGps() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return AgentReadiness.unavailable;
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return AgentReadiness.unavailable;
      }
      return AgentReadiness.ready;
    } on Object catch (_) {
      return AgentReadiness.degraded;
    }
  }

  Future<AgentReadiness> _checkSms() async {
    try {
      // Primary: server relay (Twilio / Edge) — no Android SEND_SMS required.
      final relayUrl = dotenv.env['SMS_DISPATCH_URL']?.trim() ?? '';
      final relayKey = dotenv.env['SMS_DISPATCH_ANON_KEY']?.trim() ?? '';
      if (relayUrl.isNotEmpty && relayKey.isNotEmpty) {
        return AgentReadiness.ready;
      }

      // Fallback: open SMS app intent (no permission). If relay isn't configured,
      // we mark this as degraded (still usable, but requires user interaction).
      return AgentReadiness.degraded;
    } on Object catch (_) {
      return AgentReadiness.degraded;
    }
  }

  Future<AgentReadiness> _checkBle() async {
    try {
      final status = await Permission.bluetooth.status;
      return status.isGranted ? AgentReadiness.ready : AgentReadiness.degraded;
    } on Object catch (_) {
      return AgentReadiness.degraded;
    }
  }

  void dispose() {
    stopPolling();
    if (!_controller.isClosed) _controller.close();
  }
}

final agentHealthServiceProvider = Provider<AgentHealthService>((ref) {
  final svc = AgentHealthService(ref);
  ref.onDispose(svc.dispose);
  return svc;
});
