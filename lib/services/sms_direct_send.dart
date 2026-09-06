import 'sms_direct_send_stub.dart'
    if (dart.library.io) 'sms_direct_send_io.dart';

/// Sends SMS directly on Android ([SEND_SMS]). Stub on Web; no-op on desktop/iOS targets.
Future<bool> sendSmsDirectAndroid(String number, String message) =>
    sendSmsDirectAndroidImpl(number, message);
