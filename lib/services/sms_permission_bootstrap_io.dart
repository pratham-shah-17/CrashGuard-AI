import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:permission_handler/permission_handler.dart';

import '../logging/app_log.dart';

/// Requests RECEIVE_SMS / SEND_SMS at cold start on Android.
///
/// telephony removed — deprecated and rejected by Google Play on Android 12+.
/// Uses permission_handler (already a dependency) instead.
Future<void> requestSmsPermissionEarlyIfAndroidImpl() async {
  if (kIsWeb || !Platform.isAndroid) return;
  try {
    // Intentionally no-op: direct SEND_SMS is increasingly restricted by OS/policy.
    // RoadSOS uses server relay (Twilio / Edge Function) and SMS-app intent fallback.
    await Permission
        .sms
        .status; // keep plugin warmed for health checks if needed
  } on Object catch (e, st) {
    appLog.w('Startup SMS permission request failed', error: e, stackTrace: st);
  }
}
