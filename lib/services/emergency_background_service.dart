import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

import '../logging/app_log.dart';

// MethodChannel shared with MainActivity for hardware-button events.
// We reuse it here to sync the QS tile's SharedPreferences state.
const _kHardwareButtonsChannel = MethodChannel(
  'com.codestreak.roadsos/hardware_buttons',
);

/// IPC command constants between the UI isolate and the background isolate.
class BgCommand {
  static const String startCrashMonitor = 'start_crash_monitor';
  static const String stopCrashMonitor = 'stop_crash_monitor';
  static const String startSafeWalk = 'start_safe_walk';
  static const String stopSafeWalk = 'stop_safe_walk';
  static const String sosTriggered = 'sos_triggered';
  static const String heartbeat = 'heartbeat';
  static const String drivingModeOn = 'driving_mode_on';
  static const String drivingModeOff = 'driving_mode_off';
}

const _kChannelId = 'roadsos_monitor';
const _kChannelName = 'RoadSOS Monitor';
const _kNotifId = 888;

/// Wraps flutter_background_service to provide:
///
/// 1. Crash detection continuity when the app is backgrounded / screen locked.
///    On Android without a foreground service, the OS kills the process within
///    ~30 seconds of backgrounding, silencing the accelerometer stream.
///
/// 2. Safe-walk escalation timer that persists through app switches.
///    Proactive monitor timers in the Flutter UI isolate are paused or killed
///    when Android applies app standby; the background isolate is exempt.
///
/// 3. Battery optimization exemption — requests the system to exclude this
///    app from Doze mode so the foreground service never misses a crash event.
///    Called once after the user grants the initial consent.
///
/// 4. Driving-mode notification updates — when the UI isolate detects driving
///    mode, it invokes [drivingModeOn] so the persistent notification content
///    reflects the current monitoring level.
class EmergencyBackgroundService {
  EmergencyBackgroundService._();

  static final _service = FlutterBackgroundService();
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (kIsWeb) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (_initialized) return;

    try {
      await _service.configure(
        androidConfiguration: AndroidConfiguration(
          onStart: _onStart,
          autoStart: false,
          isForegroundMode: true,
          notificationChannelId: _kChannelId,
          initialNotificationTitle: 'RoadSOS Active',
          initialNotificationContent: 'Crash detection is running.',
          foregroundServiceNotificationId: _kNotifId,
          foregroundServiceTypes: [AndroidForegroundType.location],
        ),
        iosConfiguration: IosConfiguration(
          autoStart: false,
          onForeground: _onStart,
          onBackground: _onIosBackground,
        ),
      );
      _initialized = true;
      appLog.i('[BgService] Foreground service configured.');
    } on Object catch (e, st) {
      appLog.w('[BgService] Configure failed', error: e, stackTrace: st);
    }
  }

  static Future<void> startCrashMonitor() async {
    if (!_initialized) return;
    final running = await _service.isRunning();
    if (!running) await _service.startService();
    _service.invoke(BgCommand.startCrashMonitor);
    appLog.i('[BgService] Crash monitor started.');
    _syncQsTile(active: true);
  }

  static Future<void> stopCrashMonitor() async {
    if (!_initialized) return;
    _service.invoke(BgCommand.stopCrashMonitor);
    appLog.i('[BgService] Crash monitor stopped.');
    _syncQsTile(active: false);
  }

  /// Writes the crash-monitor state to Android SharedPreferences so the
  /// Quick Settings tile reflects the current monitoring status.
  static void _syncQsTile({required bool active}) {
    if (kIsWeb || !Platform.isAndroid) return;
    _kHardwareButtonsChannel
        .invokeMethod<void>('setCrashMonitorActive', active)
        .catchError((_) {
          /* activity may not be in foreground; tile will sync on next panel open */
        });
  }

  static Future<void> startSafeWalk({required Duration duration}) async {
    if (!_initialized) return;
    final running = await _service.isRunning();
    if (!running) await _service.startService();
    _service.invoke(BgCommand.startSafeWalk, {
      'duration_seconds': duration.inSeconds,
    });
    appLog.i(
      '[BgService] Safe-walk timer started (${duration.inMinutes} min).',
    );
  }

  static Future<void> stopSafeWalk() async {
    if (!_initialized) return;
    _service.invoke(BgCommand.stopSafeWalk);
    appLog.i('[BgService] Safe-walk timer stopped.');
  }

  /// Notify the background isolate that driving mode has changed.
  /// Updates the persistent notification content to reflect the new level.
  static void notifyDrivingMode({required bool active}) {
    if (!_initialized) return;
    _service.invoke(
      active ? BgCommand.drivingModeOn : BgCommand.drivingModeOff,
    );
  }

  static Future<bool> isRunning() => _service.isRunning();

  /// Request Android battery optimization exemption (Doze exemption).
  ///
  /// Without this, Android's Doze mode restricts the foreground service's
  /// wake-lock after ~30 minutes of screen-off, potentially pausing crash
  /// detection during long drives at night.
  ///
  /// Uses [permission_handler]'s [Permission.ignoreBatteryOptimizations].
  /// On Android < 6.0 or non-Android platforms this is a safe no-op.
  static Future<void> requestBatteryOptimizationExemption() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      final status = await Permission.ignoreBatteryOptimizations.status;
      if (!status.isGranted) {
        final result = await Permission.ignoreBatteryOptimizations.request();
        appLog.i('[BgService] Battery optimization exemption: ${result.name}');
      } else {
        appLog.d('[BgService] Battery optimization exemption already granted.');
      }
    } on Object catch (e) {
      appLog.w('[BgService] Battery exemption request failed: $e');
    }
  }

  // ── Background isolate entry point ────────────────────────────────────────

  @pragma('vm:entry-point')
  static Future<void> _onStart(ServiceInstance service) async {
    if (service is AndroidServiceInstance) {
      service.on(BgCommand.startCrashMonitor).listen((_) {
        service.setForegroundNotificationInfo(
          title: 'RoadSOS — Monitoring Active',
          content: 'Crash detection running. Drive safe.',
        );
        appLog.d('[BgIsolate] Crash monitor started');
      });

      service.on(BgCommand.stopCrashMonitor).listen((_) {
        service.setForegroundNotificationInfo(
          title: 'RoadSOS',
          content: 'Monitoring paused.',
        );
      });

      service.on(BgCommand.drivingModeOn).listen((_) {
        service.setForegroundNotificationInfo(
          title: 'RoadSOS — Driving Mode',
          content: 'Crash detection armed at highway sensitivity.',
        );
      });

      service.on(BgCommand.drivingModeOff).listen((_) {
        service.setForegroundNotificationInfo(
          title: 'RoadSOS — Monitoring Active',
          content: 'Crash detection running. Drive safe.',
        );
      });

      Timer? safeWalkTimer;
      service.on(BgCommand.startSafeWalk).listen((data) {
        safeWalkTimer?.cancel();
        final seconds = (data?['duration_seconds'] as int?) ?? 1800;
        safeWalkTimer = Timer(Duration(seconds: seconds), () {
          service.invoke(BgCommand.sosTriggered, {
            'source': 'safe_walk_escalation',
          });
        });
        service.setForegroundNotificationInfo(
          title: 'RoadSOS — Safe Walk Active',
          content: 'ETA timer running. Tap to check in.',
        );
      });

      service.on(BgCommand.stopSafeWalk).listen((_) {
        safeWalkTimer?.cancel();
        safeWalkTimer = null;
        service.setForegroundNotificationInfo(
          title: 'RoadSOS — Monitoring Active',
          content: 'Crash detection running. Drive safe.',
        );
      });
    }

    Timer.periodic(const Duration(seconds: 30), (_) {
      service.invoke(BgCommand.heartbeat, {
        'ts': DateTime.now().toIso8601String(),
      });
    });
  }

  @pragma('vm:entry-point')
  static Future<bool> _onIosBackground(ServiceInstance service) async {
    WidgetsFlutterBinding.ensureInitialized();
    return true;
  }

  static Future<void> ensureNotificationChannel() async {
    if (kIsWeb || !Platform.isAndroid) return;
    final plugin = FlutterLocalNotificationsPlugin();
    const channel = AndroidNotificationChannel(
      _kChannelId,
      _kChannelName,
      description: 'Persistent notification for RoadSOS crash detection.',
      importance: Importance.low,
      showBadge: false,
    );
    await plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);
  }
}
