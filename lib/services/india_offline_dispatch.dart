import 'package:country_codes/country_codes.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:url_launcher/url_launcher.dart';

import '../logging/app_log.dart';
import 'india_emergency_routing.dart';

/// Voice / USSD paths that work with **no mobile data** when cellular voice/SMS is available.
///
/// BLE mesh is opportunistic; this layer reflects India’s typical “zero data” reality.
///
/// **Contract:** Best-effort parallel channels — opens the dialer; **not** counted toward automated
/// SMS success in [EmergencySmsDispatchService] / orchestrator (`(B)` vs primary `(A)` SEND_SMS bar).
class IndiaOfflineDispatch {
  IndiaOfflineDispatch._();

  /// SIM locale **or** GPS inside India — tourists may not use an `IN` locale.
  static bool useIndiaOfflineRouting(double lat, double lng) =>
      CountryCodes.getDeviceLocale()?.countryCode == 'IN' ||
      coordinatesRoughlyInIndia(lat, lng);

  /// After SMS/voice dispatch to 112, opens the **ambulance** parallel line (usually 108).
  /// User still confirms the dialer call (platform limitation).
  static Future<void> launchAmbulanceDeepLink(double lat, double lng) async {
    if (kIsWeb || !useIndiaOfflineRouting(lat, lng)) return;

    final route = resolveIndiaEmergencyRoute(lat, lng);
    final ambulance = route?.ambulanceNumber ?? '108';
    await _launchTel(ambulance, desc: 'ambulance $ambulance');
  }

  /// Optional USSD (e.g. carrier / state pilot codes). Set `INDIA_EMERGENCY_USSD` in `.env`
  /// to a full dial string such as `*108#` — encoded for [tel:] on Android.
  static Future<void> launchConfiguredUssd(double lat, double lng) async {
    if (kIsWeb || !useIndiaOfflineRouting(lat, lng)) return;

    final raw = dotenv.env['INDIA_EMERGENCY_USSD']?.trim();
    if (raw == null || raw.isEmpty) return;

    await _launchUssd(raw);
  }

  /// National voice ERSS (no data plan required on most carriers).
  static Future<void> launchNationalVoice112(double lat, double lng) async {
    if (kIsWeb || !useIndiaOfflineRouting(lat, lng)) return;
    await _launchTel('112', desc: '112 voice');
  }

  static Future<void> _launchTel(String digits, {required String desc}) async {
    final uri = Uri(scheme: 'tel', path: digits);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        appLog.d('India: launched $desc');
      }
    } on Object catch (e, st) {
      appLog.w('India: could not launch $desc', error: e, stackTrace: st);
    }
  }

  static Future<void> _launchUssd(String code) async {
    final uri = Uri.parse('tel:${Uri.encodeComponent(code)}');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        appLog.d('India USSD intent: $code');
      }
    } on Object catch (e, st) {
      appLog.w('India USSD launch failed', error: e, stackTrace: st);
    }
  }
}
