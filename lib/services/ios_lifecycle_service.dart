import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logging/app_log.dart';

/// Handles iOS-only lifecycle callbacks: BGTaskScheduler refresh windows, silent push wake,
/// and HealthKit observer pings (Fall samples — see README; vehicle Crash Detection is not in public HealthKit).
final iosLifecycleServiceProvider = Provider<IosLifecycleService>((ref) {
  final svc = IosLifecycleService();
  svc.attach();
  return svc;
});

class IosLifecycleService {
  IosLifecycleService();

  static const MethodChannel _channel = MethodChannel(
    'com.codestreak.roadsos/ios_lifecycle',
  );

  void attach() {
    if (kIsWeb) return;
    if (!Platform.isIOS) return;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onBackgroundPing':
          appLog.d('iOS background ping: ${call.arguments}');
          break;
        case 'onHealthKitSignal':
          appLog.w(
            'HealthKit observer fired (supplementary signal only): ${call.arguments}',
          );
          break;
        default:
          appLog.d('ios_lifecycle unknown method ${call.method}');
      }
    });
  }

  /// Ask the OS to schedule the next BGAppRefresh task (subject to budget / user patterns).
  Future<void> scheduleBackgroundRefresh() async {
    if (kIsWeb) return;
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod<void>('scheduleBackgroundRefresh');
    } on Object catch (e, st) {
      appLog.w('scheduleBackgroundRefresh failed', error: e, stackTrace: st);
    }
  }
}
