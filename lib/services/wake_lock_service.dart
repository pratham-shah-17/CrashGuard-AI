import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../logging/app_log.dart';

/// Manages the screen / CPU wake lock during an active SOS session.
///
/// During a road emergency the user's screen must stay on even if the phone
/// is lying on the seat facing down. Without this the screen dims after ~15s
/// and the dispatch status panel becomes invisible to responders who pick up
/// the phone.
///
/// Uses [wakelock_plus] which maps to:
///   Android: WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
///   iOS:     UIApplication.isIdleTimerDisabled = true
///
/// Released as soon as the SOS is cancelled or resolved. If acquisition fails
/// (desktop, web, permission error), this is a no-op so it never blocks dispatch.
class WakeLockService {
  WakeLockService._();

  static bool _held = false;

  /// Acquire wake lock for the duration of an active SOS.
  static Future<void> acquireForSos() async {
    if (kIsWeb || _held) return;
    try {
      await WakelockPlus.enable();
      _held = true;
      appLog.i('[WakeLock] Screen wake lock acquired for active SOS');
    } on Object catch (e) {
      appLog.w('[WakeLock] Failed to acquire: $e');
    }
  }

  /// Release wake lock when SOS is cancelled or resolved.
  static Future<void> release() async {
    if (kIsWeb || !_held) return;
    try {
      await WakelockPlus.disable();
      _held = false;
      appLog.d('[WakeLock] Screen wake lock released');
    } on Object catch (e) {
      appLog.w('[WakeLock] Failed to release: $e');
    }
  }

  static bool get isHeld => _held;
}
