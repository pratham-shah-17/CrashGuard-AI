import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

import '../logging/app_log.dart';

/// Sends SMS on Android using url_launcher SMS intent.
///
/// Why url_launcher instead of a direct SMS package?
/// - `telephony` is deprecated and fails on Android 12+ (SendSms no longer
///   background-sends without SEND_SMS permission, which Google Play restricts).
/// - `flutter_sms_plus` is not a published pub.dev package.
/// - `url_launcher` is already a dependency; `sms:` URIs open the native
///   Messaging app with the number and body pre-filled.
///
/// The native SMS app always works — no special permission, no Android version
/// restriction, no Google Play policy risk. The user taps Send once;
/// the pre-filled message is 160–220 chars (well within one SMS).
///
/// For automated background dispatch (Twilio / Edge Function), see
/// [EmergencySmsDispatchService._dispatchAndroid] — that path fires first and
/// only falls back here if the server relay is unavailable.
Future<bool> sendSmsDirectAndroidImpl(String number, String message) async {
  if (!Platform.isAndroid) return false;

  // Truncate to one SMS length; carrier routing adds ~40 char overhead.
  final body = message.length > 160
      ? '${message.substring(0, 157)}...'
      : message;

  // Encode body per RFC 5724 — url_launcher handles the Uri encoding.
  final uri = Uri(scheme: 'sms', path: number, queryParameters: {'body': body});

  try {
    if (!await canLaunchUrl(uri)) {
      appLog.w('[SmsDirect] Cannot launch SMS URI — no messaging app found');
      return false;
    }
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (launched) {
      appLog.d('[SmsDirect] SMS app opened for $number (user must tap Send)');
    } else {
      appLog.w('[SmsDirect] launchUrl returned false for SMS URI');
    }
    return launched;
  } on Object catch (e, st) {
    appLog.w('[SmsDirect] SMS launch failed', error: e, stackTrace: st);
    return false;
  }
}
