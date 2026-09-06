import 'dart:io' show Platform;
import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../logging/app_log.dart';

/// Service to handle emergency-specific local notifications.
class EmergencyNotificationService {
  EmergencyNotificationService._();
  static final EmergencyNotificationService instance =
      EmergencyNotificationService._();

  static const String _channelId = 'roadsos_emergency';
  static const String _channelName = 'Emergency Alerts';
  static const int _sosActiveNotificationId = 9110;

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> ensureInitialized() async {
    if (kIsWeb) return;
    if (_initialized) return;
    _initialized = true;

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();

    await _local.initialize(
      settings: const InitializationSettings(android: android, iOS: ios),
    );

    if (Platform.isAndroid) {
      const channel = AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: 'Notifications for active SOS sessions',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );
      await _local
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(channel);
    }
  }

  Future<void> showSosActiveNotification() async {
    if (kIsWeb) return;
    await ensureInitialized();

    try {
      await _local.show(
        id: _sosActiveNotificationId,
        title: '🚨 RoadSOS: Emergency Active',
        body: 'Emergency services and contacts are being notified. Stay calm.',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: 'Active SOS session alert',
            importance: Importance.max,
            priority: Priority.high,
            ongoing: true,
            autoCancel: false,
            color: Color(0xFFFF0000),
            icon: '@mipmap/ic_launcher',
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
            presentBadge: true,
          ),
        ),
      );
    } on Object catch (e, st) {
      appLog.w('Emergency local notification failed', error: e, stackTrace: st);
    }
  }

  Future<void> cancelSosNotification() async {
    if (kIsWeb) return;
    try {
      await _local.cancel(id: _sosActiveNotificationId);
    } on Object catch (_) {}
  }
}
