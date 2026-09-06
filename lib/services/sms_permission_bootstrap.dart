import 'sms_permission_bootstrap_stub.dart'
    if (dart.library.io) 'sms_permission_bootstrap_io.dart';

/// Requests [SEND_SMS] on Android early so SOS is not blocked on first send.
Future<void> requestSmsPermissionEarlyIfAndroid() =>
    requestSmsPermissionEarlyIfAndroidImpl();
