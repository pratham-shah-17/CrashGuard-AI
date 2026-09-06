import '../logging/app_log.dart';

Future<bool> sendSmsDirectAndroidImpl(String number, String message) async {
  appLog.d('Direct SMS send not available on this platform');
  return false;
}
