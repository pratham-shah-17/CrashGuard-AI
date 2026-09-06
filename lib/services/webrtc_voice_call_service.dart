import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/app_database.dart';
import '../logging/app_log.dart';

/// Phase of a WebRTC voice call from the perspective of this device.
enum VoiceCallPhase {
  idle,
  outgoing,
  incoming,
  connecting,
  connected,
  ended,
  error,
}

class VoiceCallState {
  const VoiceCallState({
    this.phase = VoiceCallPhase.idle,
    this.callId,
    this.peerId,
    this.peerName,
    this.isEmergency = false,
    this.errorMessage,
    this.startedAt,
    this.muted = false,
    this.speakerOn = true,
  });

  final VoiceCallPhase phase;
  final String? callId;
  final String? peerId;
  final String? peerName;
  final bool isEmergency;
  final String? errorMessage;
  final DateTime? startedAt;
  final bool muted;
  final bool speakerOn;

  VoiceCallState copyWith({
    VoiceCallPhase? phase,
    Object? callId = _sentinel,
    Object? peerId = _sentinel,
    Object? peerName = _sentinel,
    bool? isEmergency,
    Object? errorMessage = _sentinel,
    Object? startedAt = _sentinel,
    bool? muted,
    bool? speakerOn,
  }) {
    return VoiceCallState(
      phase: phase ?? this.phase,
      callId: identical(callId, _sentinel) ? this.callId : callId as String?,
      peerId: identical(peerId, _sentinel) ? this.peerId : peerId as String?,
      peerName: identical(peerName, _sentinel)
          ? this.peerName
          : peerName as String?,
      isEmergency: isEmergency ?? this.isEmergency,
      errorMessage: identical(errorMessage, _sentinel)
          ? this.errorMessage
          : errorMessage as String?,
      startedAt: identical(startedAt, _sentinel)
          ? this.startedAt
          : startedAt as DateTime?,
      muted: muted ?? this.muted,
      speakerOn: speakerOn ?? this.speakerOn,
    );
  }

  static const _sentinel = Object();
}

/// In-app peer-to-peer voice call between Family Circle members.
///
/// Why WebRTC (not Twilio): the user explicitly does not want a PSTN provider
/// for the hackathon demo. WebRTC works free-of-charge whenever both peers are
/// on the RoadSOS app + internet — Mom-on-feature-phone is intentionally NOT
/// supported here; that lane stays on user-initiated `tel:` dial via the
/// existing `_callEmergencyContact()` path in [EmergencyOrchestrator].
///
/// Signaling: SDP offer / answer / ICE candidates exchanged via Supabase
/// Realtime on the `voice_call_signals` table (RLS-restricted to peers who
/// share a Family Circle — see migration `20260516130000_voice_calls.sql`).
/// Media: STUN-only (Google's public servers) — no TURN, which means calls
/// behind symmetric NAT may fail. Acceptable for hackathon demo on WiFi /
/// 4G with the same operator; production should add a Coturn TURN server.
class WebRtcVoiceCallService extends StateNotifier<VoiceCallState> {
  WebRtcVoiceCallService(this._ref) : super(const VoiceCallState()) {
    _bootstrap();
  }

  // ignore: unused_field
  final Ref _ref;

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  RealtimeChannel? _ringChannel;
  RealtimeChannel? _signalChannel;
  Timer? _outgoingTimeout;
  final List<RTCIceCandidate> _pendingRemoteIce = [];

  /// Outgoing call rings for at most this long before auto-marking as
  /// `missed` and tearing down. Avoids forever-ringing when the callee's
  /// app is killed and the realtime subscription never fires.
  static const Duration _outgoingRingTimeout = Duration(seconds: 45);

  static const Map<String, dynamic> _rtcConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
  };

  bool get _hasSession {
    try {
      return isSupabaseSdkInitialized &&
          Supabase.instance.client.auth.currentSession != null;
    } on Object catch (_) {
      return false;
    }
  }

  Future<void> _bootstrap() async {
    if (kIsWeb) return;
    if (!_hasSession) return;
    await _subscribeToIncomingCalls();
  }

  Future<void> _subscribeToIncomingCalls() async {
    try {
      _ringChannel?.unsubscribe();
    } on Object catch (_) {}

    final client = Supabase.instance.client;
    final uid = client.auth.currentUser!.id;

    _ringChannel = client
        .channel('public:voice_calls:ring-$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'voice_calls',
          callback: (payload) {
            try {
              final row = (payload.newRecord as Map?)?.cast<String, dynamic>();
              if (row == null) return;
              if (row['callee_id'] != uid) return;
              if (row['state'] != 'ringing') return;
              if (state.phase != VoiceCallPhase.idle) {
                // Already in a call — auto-reject.
                unawaited(_markCall(row['id'] as String, 'declined'));
                return;
              }
              state = state.copyWith(
                phase: VoiceCallPhase.incoming,
                callId: row['id'] as String?,
                peerId: row['caller_id'] as String?,
                peerName: 'Family member',
                isEmergency: (row['is_emergency'] as bool?) ?? false,
                errorMessage: null,
                startedAt: DateTime.now(),
              );
              unawaited(_ringPulse());
            } on Object catch (e, st) {
              appLog.w('[WebRTC] ring decode failed', error: e, stackTrace: st);
            }
          },
        )
        .subscribe();
  }

  /// Place an outgoing call to a Family Circle peer.
  Future<({bool ok, String? error})> startCall({
    required String calleeId,
    String? peerName,
    bool isEmergency = false,
  }) async {
    if (kIsWeb) return (ok: false, error: 'Voice calls require mobile.');
    if (!_hasSession) {
      return (ok: false, error: 'Sign in to call your family circle.');
    }
    if (state.phase != VoiceCallPhase.idle) {
      return (ok: false, error: 'Already in a call.');
    }

    try {
      final client = Supabase.instance.client;
      final inserted = await client
          .from('voice_calls')
          .insert({
            'caller_id': client.auth.currentUser!.id,
            'callee_id': calleeId,
            'is_emergency': isEmergency,
          })
          .select('id')
          .single();
      final callId = inserted['id'] as String;

      state = state.copyWith(
        phase: VoiceCallPhase.outgoing,
        callId: callId,
        peerId: calleeId,
        peerName: peerName,
        isEmergency: isEmergency,
        startedAt: DateTime.now(),
        errorMessage: null,
      );

      await _initPeerConnection();
      await _subscribeToSignals(callId);

      final offer = await _pc!.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': false,
      });
      await _pc!.setLocalDescription(offer);
      await _sendSignal(callId, calleeId, 'offer', {
        'type': offer.type,
        'sdp': offer.sdp,
      });

      _outgoingTimeout?.cancel();
      _outgoingTimeout = Timer(_outgoingRingTimeout, () {
        if (state.phase == VoiceCallPhase.outgoing) {
          unawaited(hangup(reason: 'missed'));
        }
      });

      return (ok: true, error: null);
    } on Object catch (e, st) {
      appLog.w('[WebRTC] startCall failed', error: e, stackTrace: st);
      await _teardown();
      state = state.copyWith(
        phase: VoiceCallPhase.error,
        errorMessage: 'Could not start call: $e',
      );
      return (ok: false, error: '$e');
    }
  }

  /// Answer an incoming call.
  Future<void> answer() async {
    final callId = state.callId;
    final peerId = state.peerId;
    if (callId == null || peerId == null) return;
    if (state.phase != VoiceCallPhase.incoming) return;

    state = state.copyWith(phase: VoiceCallPhase.connecting);

    try {
      await _initPeerConnection();
      await _subscribeToSignals(callId);

      // Pull the most recent offer.
      final client = Supabase.instance.client;
      final rows = await client
          .from('voice_call_signals')
          .select('payload')
          .eq('call_id', callId)
          .eq('kind', 'offer')
          .order('created_at', ascending: false)
          .limit(1);
      if ((rows as List).isEmpty) {
        throw StateError('No SDP offer found for call $callId');
      }
      final payload = (rows.first as Map)['payload'] as Map;
      await _pc!.setRemoteDescription(
        RTCSessionDescription(
          payload['sdp'] as String,
          payload['type'] as String,
        ),
      );
      await _drainPendingIce();

      final answer = await _pc!.createAnswer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': false,
      });
      await _pc!.setLocalDescription(answer);
      await _sendSignal(callId, peerId, 'answer', {
        'type': answer.type,
        'sdp': answer.sdp,
      });

      await client
          .from('voice_calls')
          .update({
            'state': 'answered',
            'answered_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', callId);
    } on Object catch (e, st) {
      appLog.w('[WebRTC] answer failed', error: e, stackTrace: st);
      await _teardown();
      state = state.copyWith(
        phase: VoiceCallPhase.error,
        errorMessage: 'Could not answer: $e',
      );
    }
  }

  /// Decline an incoming call or hang up an in-progress one.
  Future<void> hangup({String reason = 'ended'}) async {
    final callId = state.callId;
    final peerId = state.peerId;
    if (callId != null && peerId != null) {
      try {
        await _sendSignal(callId, peerId, 'bye', {'reason': reason});
      } on Object catch (_) {}
      await _markCall(callId, reason);
    }
    await _teardown();
    state = const VoiceCallState();
  }

  Future<void> setMuted(bool muted) async {
    final tracks = _localStream?.getAudioTracks() ?? <MediaStreamTrack>[];
    for (final t in tracks) {
      t.enabled = !muted;
    }
    state = state.copyWith(muted: muted);
  }

  Future<void> toggleSpeaker(bool on) async {
    try {
      await Helper.setSpeakerphoneOn(on);
      state = state.copyWith(speakerOn: on);
    } on Object catch (e) {
      appLog.d('[WebRTC] speaker toggle failed: $e');
    }
  }

  // ── Internals ────────────────────────────────────────────────────────────

  Future<void> _initPeerConnection() async {
    _pc = await createPeerConnection(_rtcConfig);

    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': false,
    });
    for (final track in _localStream!.getAudioTracks()) {
      await _pc!.addTrack(track, _localStream!);
    }

    _pc!.onIceCandidate = (RTCIceCandidate cand) {
      final callId = state.callId;
      final peerId = state.peerId;
      if (callId == null || peerId == null) return;
      unawaited(
        _sendSignal(
          callId,
          peerId,
          'ice',
          cand.toMap() as Map<String, dynamic>,
        ),
      );
    };
    _pc!.onConnectionState = (RTCPeerConnectionState s) {
      switch (s) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          _outgoingTimeout?.cancel();
          state = state.copyWith(phase: VoiceCallPhase.connected);
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
          unawaited(hangup(reason: 'ended'));
          break;
        default:
          break;
      }
    };
  }

  Future<void> _subscribeToSignals(String callId) async {
    try {
      _signalChannel?.unsubscribe();
    } on Object catch (_) {}
    final client = Supabase.instance.client;
    _signalChannel = client
        .channel('public:voice_call_signals:call-$callId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'voice_call_signals',
          callback: (payload) async {
            try {
              final row = (payload.newRecord as Map?)?.cast<String, dynamic>();
              if (row == null) return;
              if (row['call_id'] != callId) return;
              if (row['from_user'] == client.auth.currentUser!.id) return;
              final kind = row['kind'] as String;
              final pl = (row['payload'] is String)
                  ? jsonDecode(row['payload'] as String) as Map<String, dynamic>
                  : (row['payload'] as Map).cast<String, dynamic>();
              await _handleIncomingSignal(kind, pl);
            } on Object catch (e, st) {
              appLog.d('[WebRTC] signal decode failed', stackTrace: st);
            }
          },
        )
        .subscribe();
  }

  Future<void> _handleIncomingSignal(
    String kind,
    Map<String, dynamic> payload,
  ) async {
    if (_pc == null) return;
    switch (kind) {
      case 'answer':
        await _pc!.setRemoteDescription(
          RTCSessionDescription(
            payload['sdp'] as String,
            payload['type'] as String,
          ),
        );
        await _drainPendingIce();
        break;
      case 'ice':
        final cand = RTCIceCandidate(
          payload['candidate'] as String?,
          payload['sdpMid'] as String?,
          (payload['sdpMLineIndex'] as num?)?.toInt(),
        );
        final remote = await _pc!.getRemoteDescription();
        if (remote == null) {
          _pendingRemoteIce.add(cand);
        } else {
          await _pc!.addCandidate(cand);
        }
        break;
      case 'bye':
        await hangup(reason: 'ended');
        break;
    }
  }

  Future<void> _drainPendingIce() async {
    if (_pc == null) return;
    while (_pendingRemoteIce.isNotEmpty) {
      try {
        await _pc!.addCandidate(_pendingRemoteIce.removeAt(0));
      } on Object catch (e) {
        appLog.d('[WebRTC] addCandidate pending failed: $e');
      }
    }
  }

  Future<void> _sendSignal(
    String callId,
    String toUser,
    String kind,
    Map<String, dynamic> payload,
  ) async {
    final client = Supabase.instance.client;
    await client.from('voice_call_signals').insert({
      'call_id': callId,
      'from_user': client.auth.currentUser!.id,
      'to_user': toUser,
      'kind': kind,
      'payload': payload,
    });
  }

  Future<void> _markCall(String callId, String newState) async {
    if (!_hasSession) return;
    try {
      final client = Supabase.instance.client;
      await client
          .from('voice_calls')
          .update({
            'state': newState,
            'ended_at': DateTime.now().toUtc().toIso8601String(),
            'ended_by': client.auth.currentUser!.id,
          })
          .eq('id', callId);
    } on Object catch (e) {
      appLog.d('[WebRTC] _markCall failed: $e');
    }
  }

  Future<void> _teardown() async {
    _outgoingTimeout?.cancel();
    _outgoingTimeout = null;
    try {
      await _pc?.close();
    } on Object catch (_) {}
    _pc = null;
    try {
      for (final track in (_localStream?.getTracks() ?? <MediaStreamTrack>[])) {
        await track.stop();
      }
      await _localStream?.dispose();
    } on Object catch (_) {}
    _localStream = null;
    _pendingRemoteIce.clear();
    try {
      _signalChannel?.unsubscribe();
    } on Object catch (_) {}
    _signalChannel = null;
  }

  /// Buzz the device with a recognisable triple-pulse so the user knows it's
  /// a RoadSOS call (different from a standard incoming notification).
  Future<void> _ringPulse() async {
    for (var i = 0; i < 6; i++) {
      if (state.phase != VoiceCallPhase.incoming) return;
      try {
        await HapticFeedback.heavyImpact();
        await Future<void>.delayed(const Duration(milliseconds: 180));
        await HapticFeedback.lightImpact();
      } on Object catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 900));
    }
  }

  @override
  void dispose() {
    unawaited(_teardown());
    try {
      _ringChannel?.unsubscribe();
    } on Object catch (_) {}
    super.dispose();
  }
}

final webRtcVoiceCallServiceProvider =
    StateNotifierProvider<WebRtcVoiceCallService, VoiceCallState>((ref) {
      return WebRtcVoiceCallService(ref);
    });
