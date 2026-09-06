import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:roadsos/l10n/app_localizations.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/app_database.dart';
import '../models/dispatch_channel_status.dart';
import '../models/sos_activity_record.dart';
import 'ai_triage_service.dart';
import 'location_service.dart';
import 'mesh_network_service.dart';
import 'sms_dispatch_outcome.dart';
import 'crash_detection_service.dart';
import 'voice_assistant_service.dart';
import 'user_profile_service.dart';
import '../models/facility.dart';
import '../logging/app_log.dart';
import 'app_locale_controller.dart';
import 'facility_query_service.dart';
import 'facility_sync_service.dart';
import 'sos_activity_log_service.dart';
import 'family_tracking_service.dart';
import 'family_circle_service.dart';
import 'structured_sms_service.dart';
import 'webrtc_voice_call_service.dart';
import 'privacy_consent_service.dart';
import 'driving_mode_service.dart';
import 'wake_lock_service.dart';
import 'gyroscope_fusion_service.dart';
import 'triage_validation_agent.dart';
import 'triage_feedback_service.dart';
import 'emergency_beacon_service.dart';
import 'last_scene_photo_store.dart';
import 'nearby_services_broadcast_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'emergency_notification_service.dart';

final facilityQueryServiceProvider = Provider<FacilityQueryService>((ref) {
  return FacilityQueryService();
});

final facilitySyncServiceProvider = Provider<FacilitySyncService>((ref) {
  return FacilitySyncService();
});

enum SOSPhase {
  idle,
  bystanderMode,
  countdown,
  gpsLocking,
  triaging,
  dispatching,
  active,
  resolved,
}

class SOSStatusMessage {
  final String message;
  final DateTime timestamp;
  final SOSPhase phase;
  final bool isError;

  SOSStatusMessage({
    required this.message,
    required this.phase,
    this.isError = false,
  }) : timestamp = DateTime.now();
}

class SOSState {
  final SOSPhase phase;
  final int countdownSeconds;
  final LocationFix? location;
  final TriageResult? triageResult;
  final List<SOSStatusMessage> statusLog;
  final String? incidentId;
  final List<Facility> nearbyFacilities;
  final bool isBystander;
  final List<DispatchChannelRow> dispatchChannels;
  final bool isBeaconActive;

  /// Whether the SOS was triggered while driving mode was active.
  final bool wasInDrivingMode;

  const SOSState({
    this.phase = SOSPhase.idle,
    this.countdownSeconds = 10,
    this.location,
    this.triageResult,
    this.statusLog = const [],
    this.incidentId,
    this.nearbyFacilities = const [],
    this.isBystander = false,
    this.dispatchChannels = const [],
    this.isBeaconActive = false,
    this.wasInDrivingMode = false,
  });

  SOSState copyWith({
    SOSPhase? phase,
    int? countdownSeconds,
    LocationFix? location,
    TriageResult? triageResult,
    List<SOSStatusMessage>? statusLog,
    String? incidentId,
    List<Facility>? nearbyFacilities,
    bool? isBystander,
    List<DispatchChannelRow>? dispatchChannels,
    bool? isBeaconActive,
    bool? wasInDrivingMode,
  }) {
    return SOSState(
      phase: phase ?? this.phase,
      countdownSeconds: countdownSeconds ?? this.countdownSeconds,
      location: location ?? this.location,
      triageResult: triageResult ?? this.triageResult,
      statusLog: statusLog ?? this.statusLog,
      incidentId: incidentId ?? this.incidentId,
      nearbyFacilities: nearbyFacilities ?? this.nearbyFacilities,
      isBystander: isBystander ?? this.isBystander,
      dispatchChannels: dispatchChannels ?? this.dispatchChannels,
      isBeaconActive: isBeaconActive ?? this.isBeaconActive,
      wasInDrivingMode: wasInDrivingMode ?? this.wasInDrivingMode,
    );
  }
}

/// Emergency Orchestrator — the central brain of RoadSOS.
///
/// Phase 3 — Zero-hallucination safety validation:
///   After each AI tier returns a triage, [TriageValidationAgent] enforces
///   rule-based safety constraints (ambulance mandatory at sev ≥ 3, driving
///   mode severity floor = 3, gyro crash confirmation floor = 4) before the
///   result is shown to the user or passed to dispatch channels.
///
/// Phase 5 — Multi-agent observability:
///   Dispatch channels are registered in [dispatchChannels] with per-channel
///   lifecycle tracking (pending → inProgress → success | failed | skipped).
///   The UI shows each agent's status in real-time.
///
/// Phase 7 — Hands-free voice SOS:
///   When driving mode is active at trigger, the orchestrator speaks a
///   countdown announcement and listens for a voice cancel utterance in
///   parallel with the countdown timer. After dispatch, the triage summary is
///   spoken so the driver never needs to look at the screen.
///
/// Phase 8 — RL feedback loop:
///   Initializes [TriageFeedbackService] so the severity bias is available
///   for Tier 3 / Tier 4 classifiers immediately at app start.
class EmergencyOrchestrator extends StateNotifier<SOSState> {
  final Ref _ref;
  Timer? _countdownTimer;
  final _uuid = const Uuid();
  static const Duration _sosLocationTimeout = Duration(seconds: 12);
  static const Duration _sosTriageTimeout = Duration(seconds: 10);
  static const Duration _dispatchChannelTimeout = Duration(seconds: 8);

  EmergencyOrchestrator(this._ref) : super(const SOSState()) {
    _restoreState();
    _ref.read(crashDetectionServiceProvider).startMonitoring();
    // Phase 8: ensure RL bias is loaded before any SOS fires.
    unawaited(TriageFeedbackService.instance.initialize());
  }

  Future<void> _restoreState() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('sos_active') ?? false) {
      _log('🚨 Recovering active SOS state after restart...', SOSPhase.active);
      state = state.copyWith(
        phase: SOSPhase.active,
        incidentId: prefs.getString('sos_id'),
      );
      await WakeLockService.acquireForSos();
    }
  }

  Future<void> _persistState(bool active) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sos_active', active);
    await prefs.setString('sos_id', state.incidentId ?? '');
  }

  void _log(String message, SOSPhase phase, {bool isError = false}) {
    final msg = SOSStatusMessage(
      message: message,
      phase: phase,
      isError: isError,
    );
    state = state.copyWith(statusLog: [msg, ...state.statusLog]);
    appLog.d('🚒 [ORCHESTRATOR] $message');
  }

  Future<void> startSos({bool isBystander = false}) async {
    if (state.phase != SOSPhase.idle) return;

    final isDriving = _ref.read(drivingModeProvider) == DrivingMode.driving;

    state = state.copyWith(
      phase: SOSPhase.countdown,
      countdownSeconds: 10,
      isBystander: isBystander,
      incidentId: _uuid.v4(),
      dispatchChannels: const [],
      wasInDrivingMode: isDriving,
    );

    final l10n = lookupAppLocalizations(_ref.read(appLocaleProvider));
    _log(
      isBystander
          ? l10n.orchestratorBystanderStarted
          : l10n.orchestratorSelfSosStarted,
      SOSPhase.countdown,
    );

    // Phase 7: hands-free countdown announcement when driving.
    // Spoken once at the start — no per-tick repetition to avoid interfering
    // with voice cancel listening which runs in parallel.
    if (isDriving) {
      final voice = _ref.read(voiceAssistantServiceProvider);
      unawaited(voice.speakHandsFreeCountdown(10, 'Location being acquired'));

      // Listen for voice cancel in parallel with countdown timer.
      // If the user says "cancel"/"stop"/locale equivalent → abort SOS.
      unawaited(
        voice.listenForCancel(listenFor: const Duration(seconds: 9)).then((
          cancelled,
        ) {
          if (cancelled && state.phase == SOSPhase.countdown) {
            appLog.i('[Orchestrator] Voice cancel detected — aborting SOS');
            cancelSos();
          }
        }),
      );
    }

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (state.countdownSeconds > 1) {
        state = state.copyWith(countdownSeconds: state.countdownSeconds - 1);
      } else {
        timer.cancel();
        _executeEmergencyPipeline();
      }
    });
  }

  void cancelSos() {
    _countdownTimer?.cancel();
    state = const SOSState();
    _persistState(false);
    unawaited(WakeLockService.release());
    // Stop any in-progress TTS so the countdown announcement does not keep playing.
    unawaited(_ref.read(voiceAssistantServiceProvider).stopSpeaking());
    // Phase 9: Stop hardware beacon signals.
    unawaited(EmergencyBeaconService.instance.stop());
    state = state.copyWith(isBeaconActive: false);

    unawaited(EmergencyNotificationService.instance.cancelSosNotification());
    final l10n = lookupAppLocalizations(_ref.read(appLocaleProvider));
    _log(l10n.orchestratorCancelled, SOSPhase.idle);
  }

  Future<void> _executeEmergencyPipeline() async {
    final l10n = lookupAppLocalizations(_ref.read(appLocaleProvider));
    final locale = _ref.read(appLocaleProvider);

    Future<void> failOpenToActive(String detail) async {
      _log(detail, SOSPhase.active, isError: true);
      state = state.copyWith(
        phase: SOSPhase.active,
        dispatchChannels: state.dispatchChannels.isEmpty
            ? _initialDispatchRows()
            : state.dispatchChannels,
      );
      await _persistState(true);
      unawaited(EmergencyBeaconService.instance.start());
      state = state.copyWith(isBeaconActive: true);
      await WakeLockService.acquireForSos();
    }

    _log(l10n.orchestratorAcquiringLocation, SOSPhase.gpsLocking);
    state = state.copyWith(phase: SOSPhase.gpsLocking);

    LocationFix location;
    try {
      location = await _ref
          .read(locationServiceProvider)
          .getCurrentLocation()
          .timeout(_sosLocationTimeout);
    } on Object catch (e, st) {
      appLog.w(
        '[Orchestrator] Location acquisition timed out/failed',
        error: e,
        stackTrace: st,
      );
      location = LocationFix(
        latitude: 0,
        longitude: 0,
        accuracy: 99999,
        source: 'unknown',
        timestamp: DateTime.now(),
      );
    }
    state = state.copyWith(location: location);
    final locLine = location.source == 'unknown'
        ? l10n.orchestratorLocationUnavailable
        : l10n.orchestratorLocationSecured(
            location.latitude.toStringAsFixed(3),
            location.longitude.toStringAsFixed(3),
          );
    _log(locLine, SOSPhase.gpsLocking, isError: location.source == 'unknown');

    if (location.source == 'unknown') {
      _log(
        l10n.orchestratorManualActionRequired,
        SOSPhase.dispatching,
        isError: true,
      );
      state = state.copyWith(
        phase: SOSPhase.dispatching,
        dispatchChannels: _initialDispatchRows(),
      );
      _patchDispatchChannel(
        'mesh',
        DispatchChannelLifecycle.skipped,
        'Skipped — no usable GPS fix.',
      );
      _patchDispatchChannel(
        'family_link',
        DispatchChannelLifecycle.skipped,
        'Skipped — no usable GPS fix.',
      );
      _patchDispatchChannel(
        'local_log',
        DispatchChannelLifecycle.failed,
        'Not saved — no usable GPS fix.',
      );
      _patchDispatchChannel(
        'sms',
        DispatchChannelLifecycle.inProgress,
        'Sending emergency SMS (no GPS)…',
      );
      final smsOutcome = await _dispatchSmsWithRetry(
        l10n.orchestratorSmsNoGpsPayload,
        lat: null,
        lng: null,
      );
      _patchDispatchChannel(
        'sms',
        smsOutcome.primaryAutomatedBarMet
            ? DispatchChannelLifecycle.success
            : DispatchChannelLifecycle.failed,
        smsOutcome.detail,
      );
      state = state.copyWith(phase: SOSPhase.active);
      await _persistState(true);
      await WakeLockService.acquireForSos();
      _log(
        smsOutcome.primaryAutomatedBarMet
            ? 'Emergency session active — SMS requested without GPS.'
            : 'Emergency session active — automated SMS did not succeed; dial emergency number now.',
        SOSPhase.active,
        isError: !smsOutcome.primaryAutomatedBarMet,
      );
      return;
    }

    final facilities = await _ref
        .read(facilityQueryServiceProvider)
        .queryNearby(location.latitude, location.longitude);
    state = state.copyWith(nearbyFacilities: facilities);
    unawaited(
      _ref
          .read(facilitySyncServiceProvider)
          .syncLocalRegion(location.latitude, location.longitude),
    );

    _log(l10n.orchestratorAiBrief, SOSPhase.triaging);
    state = state.copyWith(phase: SOSPhase.triaging);

    // Real sensor-derived severity hint from the most recent crash detection.
    // Falls back to a conservative default (bystander=2, driver=3) when no
    // recent crash signature exists (manual SOS button press).
    final crashHint = _ref
        .read(crashDetectionServiceProvider)
        .recentSeverityHint();
    final severityHint = crashHint ?? (state.isBystander ? 2 : 3);

    // Opportunistic scene photo: if the user (or a bystander, or the
    // Capture Scene screen) recently captured a crash-scene photo, hand it to
    // Gemma 4 27B vision. Without this, the documented "Tier 1 + vision"
    // pipeline never fired on the auto-SOS path — `scenePhoto` was hardcoded
    // to null.
    final scenePhotoStore = _ref.read(lastScenePhotoStoreProvider);
    final scenePhoto = scenePhotoStore.takeIfFresh();

    TriageResult rawTriage;
    try {
      rawTriage = await _ref
          .read(aiTriageServiceProvider)
          .performTriage(
            location: location,
            isBystander: state.isBystander,
            languageCode: locale.languageCode,
            severityHint: severityHint,
            scenePhoto: scenePhoto,
          )
          .timeout(_sosTriageTimeout);
    } on Object catch (e, st) {
      appLog.w(
        '[Orchestrator] Triage timed out/failed — using safety fallback',
        error: e,
        stackTrace: st,
      );
      rawTriage = TriageResult(
        functionCall: 'dispatch_emergency',
        location: '${location.latitude},${location.longitude}',
        severityLevel: state.isBystander ? 3 : 4,
        requiredServices: const ['ambulance', 'police'],
        firstAidQuery: 'bleeding control / airway / spinal precautions',
        compressedPayload: location.toCompressedString(),
        thinkingTrace: null,
        isDegradedMode: true,
        source: TriageSource.localTier2,
        visionUsed: false,
      );
      _log(
        'AI triage timed out — using safety fallback severity ${rawTriage.severityLevel}.',
        SOSPhase.triaging,
        isError: true,
      );
    }

    // ── Phase 3: Safety validation gate ──────────────────────────────────
    // Read gyro peak over the 1.5s window around the moment of SOS trigger.
    // The gyro service has a 3s rolling buffer so the crash peak is still in
    // memory even though a few seconds elapsed during GPS lock + triage.
    final gyroService = _ref.read(gyroscopeFusionServiceProvider);
    final gyroPeak = gyroService.peakRadPerSecAt(
      DateTime.now(),
      windowMs: 3000,
    );

    final validation = triageValidationAgent.validate(
      raw: rawTriage,
      drivingMode: _ref.read(drivingModeProvider),
      gyroPeakRadPerSec: gyroPeak,
      accelSeverityHint: severityHint,
    );

    final triage = validation.triage;
    state = state.copyWith(triageResult: triage);

    _log(l10n.orchestratorTriageDone(triage.severityLevel), SOSPhase.triaging);

    if (validation.wasOverridden) {
      _log(
        'Safety agent: ${validation.overrideNotes.length} override(s) applied. '
        'Confidence: ${triage.confidenceLabel}.',
        SOSPhase.triaging,
      );
    } else {
      _log(
        'Safety agent: triage validated — no overrides. '
        'Confidence: ${triage.confidenceLabel}.',
        SOSPhase.triaging,
      );
    }

    _log(l10n.orchestratorDispatching, SOSPhase.dispatching);
    state = state.copyWith(
      phase: SOSPhase.dispatching,
      dispatchChannels: _initialDispatchRows(),
    );

    final mesh = _ref.read(meshNetworkServiceProvider);

    _patchDispatchChannel(
      'mesh',
      DispatchChannelLifecycle.inProgress,
      'Broadcasting BLE beacon…',
    );
    _patchDispatchChannel(
      'sms',
      DispatchChannelLifecycle.inProgress,
      'Sending emergency SMS…',
    );
    _patchDispatchChannel(
      'local_log',
      DispatchChannelLifecycle.inProgress,
      'Saving incident on device…',
    );
    _patchDispatchChannel(
      'family_link',
      DispatchChannelLifecycle.inProgress,
      'Family tracking link…',
    );
    _patchDispatchChannel(
      'nearby_services',
      DispatchChannelLifecycle.inProgress,
      'Broadcasting to nearby services…',
    );

    // Phase 9: Automated alerts and calling
    unawaited(_notifyUser());
    unawaited(_callEmergencyContact());

    // Family Circle: start broadcasting SOS-mode live position to peers and
    // try a WebRTC voice ring to the first peer (only fires if signed in to
    // Supabase + the user has a circle with at least one other member).
    unawaited(_publishSosToFamilyCircle(location));
    unawaited(_ringFirstFamilyCirclePeer());

    Future<T> guard<T>({
      required String id,
      required Future<T> future,
      required T fallback,
      required String timeoutDetail,
      required String failureDetail,
    }) async {
      try {
        return await future.timeout(
          _dispatchChannelTimeout,
          onTimeout: () {
            _patchDispatchChannel(
              id,
              DispatchChannelLifecycle.failed,
              timeoutDetail,
            );
            return fallback;
          },
        );
      } on Object catch (_) {
        _patchDispatchChannel(
          id,
          DispatchChannelLifecycle.failed,
          failureDetail,
        );
        return fallback;
      }
    }

    final meshFuture =
        guard<bool>(
          id: 'mesh',
          future: mesh.startBroadcasting(
            triage.compressedPayload,
            lat: location.latitude,
            lng: location.longitude,
            severity: triage.severityLevel,
            services: triage.requiredServices,
          ),
          fallback: false,
          timeoutDetail:
              'Mesh timed out — continue with SMS and manual action.',
          failureDetail: 'Mesh failed — Bluetooth off, unsupported, or error.',
        ).then((meshOk) {
          _patchDispatchChannel(
            'mesh',
            meshOk
                ? DispatchChannelLifecycle.success
                : DispatchChannelLifecycle.failed,
            meshOk
                ? 'Mesh beacon active — nearby app users can detect you ✓'
                : 'Mesh did not start — Bluetooth off, unsupported, or failed.',
          );
          return meshOk;
        });

    // Build the rich, dispatcher-friendly SMS body. Falls back to the legacy
    // compressedPayload if the structured builder fails (must never throw).
    String smsBody;
    try {
      smsBody = await _ref
          .read(structuredSmsServiceProvider)
          .buildStructured112Sms(
            incidentId: state.incidentId ?? '',
            location: location,
            triage: triage,
          )
          .timeout(const Duration(seconds: 3));
    } on Object catch (e, st) {
      appLog.w(
        '[Orchestrator] structured SMS build failed — using legacy payload',
        error: e,
        stackTrace: st,
      );
      smsBody = triage.compressedPayload;
    }

    final smsFuture =
        guard<SmsDispatchOutcome>(
          id: 'sms',
          future: _dispatchSmsWithRetry(
            smsBody,
            lat: location.latitude,
            lng: location.longitude,
          ),
          fallback: const SmsDispatchOutcome(
            deviceDirectSmsSent: false,
            backendRelayAccepted: false,
            primaryAutomatedBarMet: false,
            proofLevel: SmsDispatchProofLevel.none,
            detail: 'SMS timed out — use dialer/manual SMS now.',
          ),
          timeoutDetail: 'SMS timed out — use dialer/manual SMS now.',
          failureDetail: 'SMS failed — use dialer/manual SMS now.',
        ).then((smsOutcome) {
          _patchDispatchChannel(
            'sms',
            smsOutcome.primaryAutomatedBarMet
                ? DispatchChannelLifecycle.success
                : DispatchChannelLifecycle.failed,
            smsOutcome.detail,
          );
          return smsOutcome;
        });

    final persistedFuture =
        guard<({bool ok, String detail})>(
          id: 'local_log',
          future: _persistIncidentSnapshot(
            incidentId: state.incidentId ?? '',
            location: location,
            triage: triage,
          ),
          fallback: (
            ok: false,
            detail: 'Local log timed out — incident not saved.',
          ),
          timeoutDetail: 'Local log timed out — incident not saved.',
          failureDetail: 'Local log failed — incident not saved.',
        ).then((persisted) {
          _patchDispatchChannel(
            'local_log',
            persisted.ok
                ? DispatchChannelLifecycle.success
                : DispatchChannelLifecycle.failed,
            persisted.detail,
          );
          return persisted;
        });

    final familyFuture =
        guard<({bool ok, String detail})>(
          id: 'family_link',
          future: _ref
              .read(familyTrackingServiceProvider)
              .registerAndNotifyContact(
                incidentId: state.incidentId ?? '',
                location: location,
                triage: triage,
              ),
          fallback: (
            ok: false,
            detail: 'Family link timed out — share manually if needed.',
          ),
          timeoutDetail: 'Family link timed out — share manually if needed.',
          failureDetail: 'Family link failed — share manually if needed.',
        ).then((family) {
          _patchDispatchChannel(
            'family_link',
            family.ok
                ? DispatchChannelLifecycle.success
                : DispatchChannelLifecycle.failed,
            family.detail,
          );
          return family;
        });

    final nearbyFuture =
        guard<NearbyBroadcastOutcome>(
          id: 'nearby_services',
          future: _ref
              .read(nearbyServicesBroadcastServiceProvider)
              .broadcast(
                incidentId: state.incidentId ?? '',
                latitude: location.latitude,
                longitude: location.longitude,
                severity: triage.severityLevel,
                requiredServices: triage.requiredServices,
                nearbyFacilityCount: state.nearbyFacilities.length,
              ),
          fallback: const NearbyBroadcastOutcome(
            ok: false,
            detail: 'Nearby services broadcast timed out.',
          ),
          timeoutDetail: 'Nearby services broadcast timed out.',
          failureDetail: 'Nearby services broadcast failed.',
        ).then((outcome) {
          _patchDispatchChannel(
            'nearby_services',
            outcome.ok
                ? DispatchChannelLifecycle.success
                : DispatchChannelLifecycle.failed,
            outcome.detail,
          );
          return outcome;
        });

    List<Object?> results;
    try {
      results = await Future.wait([
        meshFuture,
        smsFuture,
        persistedFuture,
        familyFuture,
        nearbyFuture,
      ]).timeout(_dispatchChannelTimeout + const Duration(seconds: 2));
    } on Object catch (e, st) {
      // Absolute guard: never hang in dispatching.
      appLog.w(
        '[Orchestrator] Dispatch futures did not complete in time',
        error: e,
        stackTrace: st,
      );
      await failOpenToActive(
        'Dispatch timed out — take manual action (dial emergency number).',
      );
      return;
    }

    final smsOutcome = results[1] as SmsDispatchOutcome;

    // One incident = one photo. Always release the stash so the next event
    // starts clean, regardless of whether vision tier was reached.
    scenePhotoStore.clear();

    await SosActivityLogService.instance.append(
      SosActivityRecord(
        incidentId: state.incidentId ?? '',
        completedAtUtc: DateTime.now().toUtc(),
        latitude: location.latitude,
        longitude: location.longitude,
        accuracyM: location.accuracy,
        locationSource: location.source,
        triageSeverity: triage.severityLevel,
        triageSourceName: triage.source.name,
        requiredServices: List<String>.from(triage.requiredServices),
        channels: List<DispatchChannelRow>.from(state.dispatchChannels),
        syncStatusLine: _syncStatusLineForLog(),
        isBystander: state.isBystander,
      ),
    );

    final anyConfirmed = smsOutcome.primaryAutomatedBarMet;

    state = state.copyWith(phase: SOSPhase.active);
    await _persistState(true);

    // Phase 9: Activate hardware SOS beacon (flashlight strobe + locator siren).
    unawaited(EmergencyBeaconService.instance.start());
    state = state.copyWith(isBeaconActive: true);

    // Acquire screen wake lock so the dispatch panel stays visible on a car seat.
    await WakeLockService.acquireForSos();

    _log(
      anyConfirmed
          ? 'Emergency session active — review each channel above for request status.'
          : 'Emergency session active — no automated emergency SMS request succeeded; take manual action (dial emergency number).',
      SOSPhase.active,
      isError: !anyConfirmed,
    );

    if (state.wasInDrivingMode) {
      _log(
        'SOS triggered during driving mode — incident context logged for ERSS report.',
        SOSPhase.active,
      );
    }

    // Phase 7: post-dispatch voice briefing — the driver hears what was sent.
    if (state.wasInDrivingMode) {
      final voice = _ref.read(voiceAssistantServiceProvider);
      unawaited(
        voice.speakTriageSummary(
          severity: triage.severityLevel,
          services: triage.requiredServices,
          locationCoords:
              '${location.latitude.toStringAsFixed(2)}, '
              '${location.longitude.toStringAsFixed(2)}',
        ),
      );
    }
  }

  Future<SmsDispatchOutcome> _dispatchSmsWithRetry(
    String payload, {
    double? lat,
    double? lng,
  }) async {
    final mesh = _ref.read(meshNetworkServiceProvider);
    final first = await mesh.triggerSmsFallback(payload, lat: lat, lng: lng);
    if (first.primaryAutomatedBarMet) return first;

    appLog.d('[Orchestrator] SMS attempt 1 failed — retrying in 3s');
    await Future<void>.delayed(const Duration(seconds: 3));
    final retry = await mesh.triggerSmsFallback(payload, lat: lat, lng: lng);

    if (retry.primaryAutomatedBarMet) {
      appLog.i('[Orchestrator] SMS succeeded on retry ✓');
      return SmsDispatchOutcome(
        deviceDirectSmsSent: retry.deviceDirectSmsSent,
        backendRelayAccepted: retry.backendRelayAccepted,
        primaryAutomatedBarMet: true,
        proofLevel: retry.proofLevel,
        detail: '${retry.detail} (retry)',
      );
    }

    appLog.w('[Orchestrator] SMS failed after 2 attempts');
    return retry;
  }

  List<DispatchChannelRow> _initialDispatchRows() {
    return const [
      DispatchChannelRow(
        id: 'mesh',
        title: 'Mesh beacon (BLE)',
        lifecycle: DispatchChannelLifecycle.pending,
        detail: 'Waiting…',
      ),
      DispatchChannelRow(
        id: 'sms',
        title: 'SMS to emergency number',
        lifecycle: DispatchChannelLifecycle.pending,
        detail: 'Waiting…',
      ),
      DispatchChannelRow(
        id: 'local_log',
        title: 'On-device incident log',
        lifecycle: DispatchChannelLifecycle.pending,
        detail: 'Waiting…',
      ),
      DispatchChannelRow(
        id: 'family_link',
        title: 'Family tracking link',
        lifecycle: DispatchChannelLifecycle.pending,
        detail: 'Waiting…',
      ),
      DispatchChannelRow(
        id: 'nearby_services',
        title: 'Nearby Services',
        lifecycle: DispatchChannelLifecycle.pending,
        detail: 'Waiting…',
      ),
    ];
  }

  void _patchDispatchChannel(
    String id,
    DispatchChannelLifecycle lifecycle,
    String detail,
  ) {
    final list = List<DispatchChannelRow>.from(state.dispatchChannels);
    final i = list.indexWhere((e) => e.id == id);
    if (i >= 0) {
      list[i] = list[i].copyWith(lifecycle: lifecycle, detail: detail);
      state = state.copyWith(dispatchChannels: list);
    }
  }

  Future<({bool ok, String detail})> _persistIncidentSnapshot({
    required String incidentId,
    required LocationFix location,
    required TriageResult triage,
  }) async {
    if (kIsWeb || !isDatabaseInitialized) {
      return (
        ok: false,
        detail: 'Local database unavailable — incident not saved on device.',
      );
    }
    try {
      final now = DateTime.now().toIso8601String();
      final svc = triage.requiredServices.join(',');
      final extended =
          await PrivacyConsentService.extendedRetentionForUploads();
      await appDb.execute(
        '''INSERT INTO reported_incidents (
          id, latitude, longitude, severity, services_needed, status, reported_at, created_at, extended_retention
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)''',
        [
          incidentId,
          location.latitude,
          location.longitude,
          triage.severityLevel,
          svc,
          'dispatched',
          now,
          now,
          extended ? 1 : 0,
        ],
      );
      return (
        ok: true,
        detail: _hasSupabaseSession()
            ? 'Saved on device. Sync is enabled when network allows.'
            : 'Saved on device. Cloud sync needs Supabase credentials.',
      );
    } on Object catch (e, st) {
      appLog.w('Local incident insert failed', error: e, stackTrace: st);
      return (ok: false, detail: 'Could not save incident log on device.');
    }
  }

  bool _hasSupabaseSession() {
    try {
      return Supabase.instance.client.auth.currentSession != null;
    } on Object catch (_) {
      return false;
    }
  }

  String _syncStatusLineForLog() {
    if (kIsWeb) return 'Web — local encrypted incident log unavailable.';
    if (!isDatabaseInitialized) {
      return 'Local database off — incident row not stored on device.';
    }
    if (_hasSupabaseSession()) {
      return 'Saved on phone — sync enabled when network allows.';
    }
    return 'Saved on phone — enable Supabase anonymous auth for cloud backup.';
  }

  void triggerSOS() => startSos();
  void cancelSOS() => cancelSos();

  Future<void> _callEmergencyContact() async {
    final profile = _ref.read(userProfileProvider);
    final contact = profile.emergencyContact.trim();
    if (contact.isEmpty) {
      appLog.w('[Orchestrator] No emergency contact found to call.');
      return;
    }

    final uri = Uri.parse('tel:$contact');
    try {
      if (await canLaunchUrl(uri)) {
        appLog.i('[Orchestrator] Initiating automated call to $contact');
        await launchUrl(uri);
      } else {
        appLog.w('[Orchestrator] Could not launch dialer for $contact');
      }
    } on Object catch (e, st) {
      appLog.e(
        '[Orchestrator] Error launching dialer',
        error: e,
        stackTrace: st,
      );
    }
  }

  Future<void> _notifyUser() async {
    await EmergencyNotificationService.instance.showSosActiveNotification();
  }

  Future<void> _publishSosToFamilyCircle(LocationFix location) async {
    try {
      final profile = _ref.read(userProfileProvider);
      await _ref
          .read(familyCircleServiceProvider.notifier)
          .startPublishing(
            mode: FamilyPublishMode.sos,
            displayName: profile.fullName.trim().isEmpty
                ? 'RoadSOS user'
                : profile.fullName.trim(),
          );
    } on Object catch (e, st) {
      appLog.d(
        '[Orchestrator] family circle SOS publish failed',
        stackTrace: st,
      );
    }
  }

  Future<void> _ringFirstFamilyCirclePeer() async {
    try {
      final circle = _ref.read(familyCircleServiceProvider);
      if (circle.members.isEmpty) return;
      String? client;
      try {
        client = Supabase.instance.client.auth.currentUser?.id;
      } on Object catch (_) {}
      if (client == null) return;
      // Find the first member that is NOT the current user.
      final peer = circle.members.firstWhere(
        (m) => m.userId != client,
        orElse: () => circle.members.first,
      );
      if (peer.userId == client) return;
      final res = await _ref
          .read(webRtcVoiceCallServiceProvider.notifier)
          .startCall(
            calleeId: peer.userId,
            peerName: peer.displayName,
            isEmergency: true,
          );
      if (res.error != null) {
        appLog.d('[Orchestrator] family ring skipped: ${res.error}');
      }
    } on Object catch (e, st) {
      appLog.d('[Orchestrator] family ring failed', stackTrace: st);
    }
  }
}

final emergencyOrchestratorProvider =
    StateNotifierProvider<EmergencyOrchestrator, SOSState>((ref) {
      return EmergencyOrchestrator(ref);
    });

final voiceAssistantServiceProvider = Provider<VoiceAssistantService>((ref) {
  return VoiceAssistantService();
});

final userProfileServiceProvider = Provider<UserProfileService>((ref) {
  return UserProfileService();
});
