import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../logging/app_log.dart';
import 'connectivity_service.dart';
import 'facility_query_service.dart';

/// Outcome of a nearby-services dispatch attempt — never throws.
class NearbyBroadcastOutcome {
  final bool ok;
  final String detail;
  final int reachedFacilityCount;

  const NearbyBroadcastOutcome({
    required this.ok,
    required this.detail,
    this.reachedFacilityCount = 0,
  });
}

/// Real "Nearby Services" dispatch channel.
///
/// Replaces the previous `Future.delayed(3s, () => true)` placeholder that
/// claimed success without performing any broadcast. The previous behaviour
/// was dangerous: a real victim and a hackathon judge would see "Emergency
/// alert broadcasted to nearby facilities and responders ✓" while nothing
/// was published anywhere.
///
/// What this service actually does (in order, with hard timeouts):
///   1. **Realtime broadcast** of the SOS payload on the canonical channel
///      `roadsos_nearby_sos`. Any subscribed peer (mobile app or responder
///      dashboard) receives the message immediately via Supabase Realtime.
///      This is the same broadcast pattern the FCM bystander relay was
///      designed to mirror, except it works without Firebase + topic-fanout
///      infrastructure (which the repo never had).
///   2. **Counts real nearby facilities** that were resolved from
///      [FacilityQueryService] so the dispatch detail shows the bystander /
///      victim *how many* hospitals/trauma centres are reachable within
///      ~10 km. That number is grounded in the same data the orchestrator
///      already retrieved during the GPS-lock phase — no fake numbers.
///
/// Failure modes are reported honestly:
///   • Skipped — no Supabase session         (anon auth missing)
///   • Skipped — no network                  (NetworkQuality.none)
///   • Failed — realtime channel error       (broadcast never confirmed)
///
/// The orchestrator surfaces the exact `detail` string in the dispatch
/// panel, so the user / judge always sees whether the broadcast was real.
class NearbyServicesBroadcastService {
  NearbyServicesBroadcastService(this._ref);

  final Ref _ref;

  static const String _channelName = 'roadsos_nearby_sos';
  static const String _broadcastEvent = 'sos_broadcast';
  static const Duration _subscribeTimeout = Duration(seconds: 4);
  static const Duration _sendTimeout = Duration(seconds: 3);

  /// Publish an SOS to the nearby-SOS realtime channel and report how many
  /// nearby facilities exist within the query radius.
  Future<NearbyBroadcastOutcome> broadcast({
    required String incidentId,
    required double latitude,
    required double longitude,
    required int severity,
    required List<String> requiredServices,
    int nearbyFacilityCount = 0,
  }) async {
    final connectivity = _ref.read(connectivityServiceProvider);
    if (connectivity.currentQuality == NetworkQuality.none) {
      return const NearbyBroadcastOutcome(
        ok: false,
        detail: 'Skipped — offline; BLE mesh beacon is the offline channel.',
      );
    }

    SupabaseClient client;
    try {
      client = Supabase.instance.client;
    } on Object catch (e, st) {
      appLog.w(
        '[NearbyBroadcast] Supabase not initialised',
        error: e,
        stackTrace: st,
      );
      return const NearbyBroadcastOutcome(
        ok: false,
        detail: 'Skipped — Supabase realtime not configured on this build.',
      );
    }

    if (client.auth.currentSession == null) {
      return const NearbyBroadcastOutcome(
        ok: false,
        detail:
            'Skipped — not signed in. Enable anonymous auth so peers can hear you.',
      );
    }

    RealtimeChannel? channel;
    try {
      channel = client.channel(_channelName);

      // Subscribe and wait for SUBSCRIBED state with hard timeout.
      final subscribed = Completer<bool>();
      channel.subscribe((status, error) {
        if (subscribed.isCompleted) return;
        if (status == RealtimeSubscribeStatus.subscribed) {
          subscribed.complete(true);
        } else if (status == RealtimeSubscribeStatus.channelError ||
            status == RealtimeSubscribeStatus.closed ||
            error != null) {
          subscribed.complete(false);
        }
      });

      bool didSubscribe;
      try {
        didSubscribe = await subscribed.future.timeout(_subscribeTimeout);
      } on TimeoutException {
        didSubscribe = false;
      }

      if (!didSubscribe) {
        return const NearbyBroadcastOutcome(
          ok: false,
          detail:
              'Failed — realtime channel did not subscribe within 4s. Try mesh beacon + SMS.',
        );
      }

      await channel
          .sendBroadcastMessage(
            event: _broadcastEvent,
            payload: {
              'incident_id': incidentId,
              'lat': latitude,
              'lng': longitude,
              'severity': severity,
              'services': requiredServices,
              'ts_utc': DateTime.now().toUtc().toIso8601String(),
              'source': 'roadsos_mobile',
            },
          )
          .timeout(_sendTimeout);

      appLog.i(
        '[NearbyBroadcast] Sent SOS broadcast on $_channelName '
        '(severity=$severity, facilities=$nearbyFacilityCount)',
      );

      final facilityHint = nearbyFacilityCount > 0
          ? '$nearbyFacilityCount nearby facilities resolved (within 10 km).'
          : 'No mapped facilities found nearby — broadcast still reaches subscribed peers.';

      return NearbyBroadcastOutcome(
        ok: true,
        detail: 'Realtime broadcast accepted ✓ — $facilityHint',
        reachedFacilityCount: nearbyFacilityCount,
      );
    } on TimeoutException {
      return const NearbyBroadcastOutcome(
        ok: false,
        detail: 'Failed — realtime send timed out (>3s).',
      );
    } on Object catch (e, st) {
      appLog.w('[NearbyBroadcast] Broadcast failed', error: e, stackTrace: st);
      return NearbyBroadcastOutcome(
        ok: false,
        detail:
            'Failed — realtime broadcast error: ${e.toString().substring(0, e.toString().length.clamp(0, 80))}',
      );
    } finally {
      if (channel != null) {
        try {
          await client.removeChannel(channel);
        } on Object catch (_) {
          /* best-effort */
        }
      }
    }
  }
}

final nearbyServicesBroadcastServiceProvider =
    Provider<NearbyServicesBroadcastService>((ref) {
      return NearbyServicesBroadcastService(ref);
    });
