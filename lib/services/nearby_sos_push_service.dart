import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import '../app_navigator.dart';
import '../logging/app_log.dart';
import 'privacy_consent_service.dart';
import 'nearby_sos_preferences.dart';

/// Firebase Cloud Messaging for opt-in “Nearby SOS” bystander alerts.
/// Requires `google-services.json` (Android) / Firebase iOS setup; otherwise init fails gracefully.
class NearbySosPushService {
  NearbySosPushService._();
  static final instance = NearbySosPushService._();

  static const _topic = 'roadsos_nearby_sos';
  final _local = FlutterLocalNotificationsPlugin();
  var _initialized = false;
  var _firebaseAvailable = false;

  bool get firebaseAvailable => _firebaseAvailable;

  Future<void> configureAfterConsentIfNeeded() async {
    if (!await PrivacyConsentService.hasConsent()) return;
    if (!await NearbySosPreferences.pushOptIn()) return;

    if (await Permission.notification.isDenied) {
      final s = await Permission.notification.request();
      if (!s.isGranted) {
        appLog.w('Notification permission denied — Nearby SOS push disabled.');
        await NearbySosPreferences.setPushOptIn(false);
        return;
      }
    }

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
    } on Object catch (e, st) {
      appLog.w(
        'Firebase not configured (add google-services.json / FirebaseOptions). Nearby SOS push disabled.',
        error: e,
        stackTrace: st,
      );
      _firebaseAvailable = false;
      return;
    }
    _firebaseAvailable = true;

    if (_initialized) {
      await _syncSubscription();
      return;
    }
    _initialized = true;

    await _initLocalNotifications();
    await _syncSubscription();

    final messaging = FirebaseMessaging.instance;
    if (Platform.isIOS) {
      await messaging.requestPermission(alert: true, badge: true, sound: true);
    }
    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_onOpenFromBackground);
    messaging.getInitialMessage().then((m) {
      if (m != null) _onOpenFromBackground(m);
    });

    appLog.i('Nearby SOS FCM handlers registered (topic $_topic).');
  }

  Future<void> _syncSubscription() async {
    final optIn = await NearbySosPreferences.pushOptIn();
    try {
      final messaging = FirebaseMessaging.instance;
      if (optIn) {
        await messaging.subscribeToTopic(_topic);
      } else {
        await messaging.unsubscribeFromTopic(_topic);
      }
    } on Object catch (e, st) {
      appLog.w(
        'FCM topic subscribe/unsubscribe failed',
        error: e,
        stackTrace: st,
      );
    }
  }

  Future<void> _initLocalNotifications() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    await _local.initialize(
      settings: const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: _onTapLocalNotification,
    );

    const channel = AndroidNotificationChannel(
      'roadsos_nearby_sos',
      'Nearby SOS',
      description: 'Alerts when another user nearby triggers SOS',
      importance: Importance.high,
    );
    await _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);
  }

  void _onTapLocalNotification(NotificationResponse response) {
    final ctx = appNavigatorKey.currentContext;
    if (ctx != null && ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(
          content: Text('Open Settings → Nearby SOS for Good Samaritan info.'),
        ),
      );
    }
  }

  Future<void> _onForegroundMessage(RemoteMessage message) async {
    final title = message.notification?.title ?? 'Nearby SOS';
    final body =
        message.notification?.body ??
        message.data['body']?.toString() ??
        'Someone nearby may need help.';

    await _local.show(
      id: message.hashCode,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'roadsos_nearby_sos',
          'Nearby SOS',
          channelDescription: 'Bystander alerts',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: 'nearby_sos',
    );

    final ctx = appNavigatorKey.currentContext;
    if (ctx != null && ctx.mounted) {
      ScaffoldMessenger.of(
        ctx,
      ).showSnackBar(SnackBar(content: Text('$title — $body')));
    }
  }

  void _onOpenFromBackground(RemoteMessage message) {
    final ctx = appNavigatorKey.currentContext;
    if (ctx != null && ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text(message.notification?.title ?? 'Nearby SOS alert'),
        ),
      );
    }
  }

  /// Call when user toggles opt-in from Settings (after consent exists).
  Future<bool> onOptInChanged(bool enabled) async {
    await NearbySosPreferences.setPushOptIn(enabled);
    await configureAfterConsentIfNeeded();
    if (enabled && !_firebaseAvailable) {
      await NearbySosPreferences.setPushOptIn(false);
      return false;
    }
    if (!enabled) {
      try {
        await FirebaseMessaging.instance.unsubscribeFromTopic(_topic);
      } on Object catch (_) {}
    }
    return true;
  }
}
