import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'emergency_orchestrator.dart';
import 'family_circle_service.dart';
import 'safe_walk_notification_service.dart';

class ProactiveMonitorState {
  final bool isMonitoring;
  final String? destination;
  final DateTime? eta;
  final bool alertTriggered;

  ProactiveMonitorState({
    this.isMonitoring = false,
    this.destination,
    this.eta,
    this.alertTriggered = false,
  });

  ProactiveMonitorState copyWith({
    bool? isMonitoring,
    String? destination,
    DateTime? eta,
    bool? alertTriggered,
  }) {
    return ProactiveMonitorState(
      isMonitoring: isMonitoring ?? this.isMonitoring,
      destination: destination ?? this.destination,
      eta: eta ?? this.eta,
      alertTriggered: alertTriggered ?? this.alertTriggered,
    );
  }
}

class ProactiveMonitorService extends StateNotifier<ProactiveMonitorState> {
  ProactiveMonitorService(this._ref) : super(ProactiveMonitorState());

  final Ref _ref;
  Timer? _monitorTimer;
  Timer? _escalationTimer;

  @override
  void dispose() {
    _monitorTimer?.cancel();
    _escalationTimer?.cancel();
    super.dispose();
  }

  void startSafeWalk(String dest, Duration duration) {
    _monitorTimer?.cancel();
    _escalationTimer?.cancel();

    state = state.copyWith(
      isMonitoring: true,
      destination: dest,
      eta: DateTime.now().add(duration),
      alertTriggered: false,
    );

    _monitorTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _checkSafety();
    });

    // Go live for Family Circle peers. Fail-soft — if Supabase is offline or
    // the user has no circle, this becomes a no-op and the timer-only Safe
    // Walk still works.
    unawaited(
      _ref
          .read(familyCircleServiceProvider.notifier)
          .startPublishing(mode: FamilyPublishMode.safeWalk, destination: dest),
    );
  }

  void _checkSafety() {
    if (state.eta != null && DateTime.now().isAfter(state.eta!)) {
      _triggerCheckIn();
    }
  }

  void _triggerCheckIn() {
    state = state.copyWith(alertTriggered: true);

    final dest = state.destination ?? 'your destination';
    final orchestrator = _ref.read(emergencyOrchestratorProvider.notifier);
    SafeWalkNotificationService.instance.ensureInitialized(
      orchestrator: orchestrator,
      monitor: this,
    );
    SafeWalkNotificationService.instance.showCheckInNow(destination: dest);
    SafeWalkNotificationService.instance.showForegroundDialogIfPossible(
      destination: dest,
      monitor: this,
    );

    _escalationTimer?.cancel();
    _escalationTimer = Timer(const Duration(seconds: 60), () {
      if (!state.isMonitoring || !state.alertTriggered) return;
      _ref.read(emergencyOrchestratorProvider.notifier).triggerSOS();
    });
  }

  void confirmImSafe() {
    if (!state.isMonitoring) return;
    _escalationTimer?.cancel();
    state = state.copyWith(alertTriggered: false);
    SafeWalkNotificationService.instance.cancelCheckInNotification();
  }

  void escalateToSosNow() {
    if (!state.isMonitoring) return;
    SafeWalkNotificationService.instance.cancelCheckInNotification();
    _ref.read(emergencyOrchestratorProvider.notifier).triggerSOS();
  }

  void endSafeWalk() {
    _monitorTimer?.cancel();
    _escalationTimer?.cancel();
    SafeWalkNotificationService.instance.cancelCheckInNotification();
    unawaited(_ref.read(familyCircleServiceProvider.notifier).stopPublishing());
    state = ProactiveMonitorState();
  }
}

/// IMPORTANT: NOT autoDispose.
///
/// The previous autoDispose caused the safe-walk escalation timer to be killed
/// whenever any widget watching this provider was rebuilt or removed from the
/// widget tree — e.g., when the user navigated from Dashboard to Settings.
/// The escalation must survive widget lifecycle changes to guarantee the 60s
/// SOS escalation fires even when the app is in the background.
final proactiveMonitorProvider =
    StateNotifierProvider<ProactiveMonitorService, ProactiveMonitorState>((
      ref,
    ) {
      return ProactiveMonitorService(ref);
    });
