import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../app_navigator.dart';
import '../logging/app_log.dart';
import 'emergency_orchestrator.dart';
import 'proactive_monitor_service.dart';

/// Local notification + action handling for Safe Walk check-ins.
///
/// Goal: if ETA is missed, prompt user to confirm they're safe before escalating to SOS.
class SafeWalkNotificationService {
  SafeWalkNotificationService._();

  static final SafeWalkNotificationService instance =
      SafeWalkNotificationService._();

  static const String _channelId = 'roadsos_safe_walk';
  static const String _channelName = 'Safe Walk';

  static const int _checkInNotificationId = 8801;

  static const String actionImSafe = 'SAFE_WALK_IM_SAFE';
  static const String actionSosNow = 'SAFE_WALK_SOS_NOW';

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<void> ensureInitialized({
    required EmergencyOrchestrator orchestrator,
    required ProactiveMonitorService monitor,
  }) async {
    if (kIsWeb) return;
    if (_initialized) return;
    _initialized = true;

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();

    await _local.initialize(
      settings: const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: (response) async {
        final actionId = response.actionId ?? '';
        if (actionId == actionImSafe) {
          monitor.confirmImSafe();
          return;
        }
        if (actionId == actionSosNow) {
          orchestrator.triggerSOS();
          return;
        }
      },
    );

    if (Platform.isAndroid) {
      const channel = AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: 'Check-ins and reminders for Safe Walk',
        importance: Importance.high,
      );
      await _local
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(channel);
    }
  }

  Future<void> showCheckInNow({required String destination}) async {
    if (kIsWeb) return;

    try {
      await _local.show(
        id: _checkInNotificationId,
        title: 'Safe Walk check-in',
        body: 'Are you safe? Destination: $destination',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: 'Safe Walk check-ins',
            importance: Importance.high,
            priority: Priority.high,
            actions: <AndroidNotificationAction>[
              AndroidNotificationAction(
                actionImSafe,
                "I'M SAFE",
                showsUserInterface: true,
                cancelNotification: true,
              ),
              AndroidNotificationAction(
                actionSosNow,
                'SOS NOW',
                showsUserInterface: true,
                cancelNotification: true,
              ),
            ],
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
    } on Object catch (e, st) {
      appLog.w('Safe Walk local notification failed', error: e, stackTrace: st);
    }
  }

  Future<void> cancelCheckInNotification() async {
    try {
      await _local.cancel(id: _checkInNotificationId);
    } on Object catch (_) {}
  }

  /// Best-effort foreground prompt for users already in-app.
  void showForegroundDialogIfPossible({
    required String destination,
    required ProactiveMonitorService monitor,
  }) {
    final ctx = appNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;

    // Avoid stacking dialogs.
    showDialog<void>(
      context: ctx,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Safe Walk check-in'),
          content: Text('Are you safe? Destination: $destination'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                monitor.confirmImSafe();
              },
              child: const Text("I'M SAFE"),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                monitor.escalateToSosNow();
              },
              child: const Text('SOS NOW'),
            ),
          ],
        );
      },
    );
  }
}
