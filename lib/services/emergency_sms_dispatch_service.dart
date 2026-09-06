import 'dart:async';
import 'dart:convert';

import 'package:country_codes/country_codes.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../logging/app_log.dart';
import 'india_emergency_routing.dart';
import 'sms_direct_send.dart';
import 'sms_dispatch_outcome.dart';

/// Routes SOS SMS by platform and region:
/// - **Android**: When [SMS_DISPATCH_URL] + [SMS_DISPATCH_ANON_KEY] are set, POST there first (Twilio / Edge).
///   Otherwise (or after relay failure) uses [SEND_SMS] + Telephony API.
/// - **iOS**: POST to [SMS_DISPATCH_URL] only (cannot send SMS directly).
/// - **India**: Prefer [INDIA_SOS_DISPATCH_URL], optional [INDIA_ERSS_API_URL] (MHA/CDAC enrollment).
///
/// **Dispatch success contract (v1 India / Android):**
/// - **(A)** Primary automated bar: [SmsDispatchOutcome.primaryAutomatedBarMet] — **device** [SEND_SMS] to
///   112/911, *or* (iOS only) HTTP relay 2xx, *or* (Android) HTTP relay 2xx only if
///   `SMS_RELAY_COUNTS_AS_PRIMARY_DISPATCH=true` (audited backend that actually delivers to 112).
/// - **(B)** Parallel **108** dial / USSD — [IndiaOfflineDispatch]; dialer only, not dispatch proof.
/// - **(C)** [INDIA_ERSS_API_URL] is optional telemetry; never gates outcome.
class EmergencySmsDispatchService {
  EmergencySmsDispatchService._();

  static String emergencyNumberForLocale() {
    final override = dotenv.env['EMERGENCY_NUMBER_OVERRIDE']?.trim();
    if (override != null && override.isNotEmpty) return override;

    final countryCode = CountryCodes.getDeviceLocale()?.countryCode;
    // Minimal routing table (expand as needed). Defaults to 112 where supported.
    // Note: this is not a substitute for server-side reverse-geocode routing when online.
    const uses911 = <String>{
      'US',
      'CA',
      'MX',
      'DO',
      'PR',
      'PA',
      'BS',
      'JM',
      'BM',
    };
    const uses112 = <String>{
      'IN',
      'GB',
      'IE',
      'FR',
      'DE',
      'ES',
      'PT',
      'IT',
      'NL',
      'BE',
      'SE',
      'NO',
      'DK',
      'FI',
      'PL',
      'CZ',
      'AT',
      'CH',
      'HU',
      'RO',
      'BG',
      'GR',
      'TR',
    };
    if (countryCode != null && uses911.contains(countryCode)) return '911';
    if (countryCode != null && uses112.contains(countryCode)) return '112';
    // Fallback: 112 is widely supported internationally (GSM); for unsupported countries,
    // the user must still be able to dial manually from UI.
    final fallback = dotenv.env['EMERGENCY_NUMBER_FALLBACK']?.trim();
    if (fallback != null && fallback.isNotEmpty) return fallback;
    return '112';
  }

  /// Android: direct device send always satisfies (A). HTTP relay 2xx only if
  /// [SMS_RELAY_COUNTS_AS_PRIMARY_DISPATCH] is set. iOS: HTTP relay 2xx is the only automated path.
  static bool _primaryAutomatedBar({
    required bool deviceDirectSmsSent,
    required bool backendRelayAccepted,
  }) {
    if (deviceDirectSmsSent) return true;
    if (!backendRelayAccepted) return false;
    if (defaultTargetPlatform == TargetPlatform.iOS) return true;
    final v = dotenv.env['SMS_RELAY_COUNTS_AS_PRIMARY_DISPATCH']
        ?.trim()
        .toLowerCase();
    return v == 'true' || v == '1' || v == 'yes';
  }

  static SmsDispatchOutcome _outcome({
    required bool device,
    required bool relay,
    required String detail,
  }) {
    final primary = _primaryAutomatedBar(
      deviceDirectSmsSent: device,
      backendRelayAccepted: relay,
    );
    return SmsDispatchOutcome(
      deviceDirectSmsSent: device,
      backendRelayAccepted: relay,
      primaryAutomatedBarMet: primary,
      proofLevel: (device || relay)
          ? SmsDispatchProofLevel.accepted
          : SmsDispatchProofLevel.none,
      detail: detail,
    );
  }

  /// Single entry for mesh / orchestrator SOS path.
  static Future<SmsDispatchOutcome> dispatch({
    required String payload,
    double? lat,
    double? lng,
  }) async {
    if (kIsWeb) {
      return _outcome(
        device: false,
        relay: false,
        detail: 'SMS unavailable on web — install the app on a phone.',
      );
    }

    final cc = CountryCodes.getDeviceLocale()?.countryCode;
    final body = _composeBody(payload, lat, lng);
    final emergencyNum = emergencyNumberForLocale();

    // (C) Optional ERSS ingest — must not affect return value below.
    if (lat != null && lng != null && coordinatesRoughlyInIndia(lat, lng)) {
      final erssUrl = dotenv.env['INDIA_ERSS_API_URL']?.trim();
      if (erssUrl != null && erssUrl.isNotEmpty) {
        unawaited(_postIndiaErssIngest(erssUrl, payload, lat, lng));
      }
    }

    // India — server-side relay when enrolled (MoHA / state ERSS integrations).
    final inIndiaContext =
        cc == 'IN' ||
        (lat != null && lng != null && coordinatesRoughlyInIndia(lat, lng));
    if (inIndiaContext) {
      final indiaUrl = dotenv.env['INDIA_SOS_DISPATCH_URL']?.trim();
      final indiaDest =
          (dotenv.env['INDIA_EMERGENCY_NUMBER']?.trim().isNotEmpty ?? false)
          ? dotenv.env['INDIA_EMERGENCY_NUMBER']!.trim()
          : '112';
      final route =
          lat != null && lng != null && coordinatesRoughlyInIndia(lat, lng)
          ? resolveIndiaEmergencyRoute(lat, lng)
          : null;
      if (indiaUrl != null && indiaUrl.isNotEmpty) {
        final ok = await _postJson(indiaUrl, <String, dynamic>{
          'channel': 'india_emergency_sms',
          'country_code': 'IN',
          'destination': indiaDest,
          'payload': payload,
          'latitude': lat,
          'longitude': lng,
          'body': body,
          if (route != null) ...<String, dynamic>{
            'state_code': route.stateCode,
            'state_name': route.stateName,
            'ambulance_number': route.ambulanceNumber,
            'police_number': route.policeNumber,
            'fire_number': route.fireNumber,
          },
        });
        if (ok) {
          appLog.d('SMS India relay accepted');
          final primary = _primaryAutomatedBar(
            deviceDirectSmsSent: false,
            backendRelayAccepted: true,
          );
          final detail = primary
              ? 'India relay accepted ✓ (request handed off; not delivery-proof)'
              : 'India relay HTTP 2xx ✓ — primary (A) bar needs device SEND_SMS or '
                    'SMS_RELAY_COUNTS_AS_PRIMARY_DISPATCH=true (audited SMS to 112).';
          return _outcome(device: false, relay: true, detail: detail);
        }
        appLog.w(
          'SMS India relay failed; falling back to device SMS where allowed',
        );
      }
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return _dispatchIosBackend(cc, payload, lat, lng, body, emergencyNum);
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      return _dispatchAndroid(cc, payload, lat, lng, body, emergencyNum);
    }

    appLog.w('Unsupported platform for automatic SMS');
    return _outcome(
      device: false,
      relay: false,
      detail: 'Automatic SMS not available on this device.',
    );
  }

  static Future<SmsDispatchOutcome> _dispatchIosBackend(
    String? cc,
    String payload,
    double? lat,
    double? lng,
    String body,
    String emergencyNum,
  ) async {
    final url = dotenv.env['SMS_DISPATCH_URL']?.trim();
    if (url == null || url.isEmpty) {
      appLog.w(
        'iOS: set SMS_DISPATCH_URL for server-side SMS (Twilio/Edge). '
        'Cannot auto-send SMS on iOS.',
      );
      return _outcome(
        device: false,
        relay: false,
        detail:
            'SMS did not send automatically on iOS — configure SMS_DISPATCH_URL or dial $emergencyNum manually.',
      );
    }
    final ok = await _postJson(url, <String, dynamic>{
      'channel': 'twilio_backend',
      'destination': emergencyNum,
      'country_code': cc,
      'payload': payload,
      'latitude': lat,
      'longitude': lng,
      'body': body,
    });
    if (ok) {
      appLog.d('iOS backend SMS dispatch sent');
      return _outcome(
        device: false,
        relay: true,
        detail:
            'SMS relay accepted for $emergencyNum ✓ (request handed off; not delivery-proof)',
      );
    }
    appLog.w('iOS backend SMS dispatch failed');
    return _outcome(
      device: false,
      relay: false,
      detail: 'SMS relay request failed — check network and SMS_DISPATCH_URL.',
    );
  }

  /// Prefer [SMS_DISPATCH_URL] (Twilio / Supabase Edge) when configured; fall back to device [SEND_SMS].
  static Future<SmsDispatchOutcome> _dispatchAndroid(
    String? cc,
    String payload,
    double? lat,
    double? lng,
    String body,
    String number,
  ) async {
    final relayUrl = dotenv.env['SMS_DISPATCH_URL']?.trim();
    if (relayUrl != null && relayUrl.isNotEmpty) {
      final relayOk = await _postJson(relayUrl, <String, dynamic>{
        'channel': 'twilio_backend',
        'destination': number,
        'country_code': cc,
        'payload': payload,
        'latitude': lat,
        'longitude': lng,
        'body': body,
      });
      if (relayOk) {
        appLog.d(
          'Android SMS dispatched via SMS_DISPATCH_URL (Twilio/backend)',
        );
        final primary = _primaryAutomatedBar(
          deviceDirectSmsSent: false,
          backendRelayAccepted: true,
        );
        final detail = primary
            ? 'Backend relay accepted for $number ✓ (request handed off; not delivery-proof)'
            : 'Backend relay HTTP 2xx ✓ — primary bar needs device SEND_SMS or '
                  'SMS_RELAY_COUNTS_AS_PRIMARY_DISPATCH=true.';
        return _outcome(device: false, relay: true, detail: detail);
      }
      appLog.w(
        'Android backend SMS failed or unavailable — falling back to direct SEND_SMS',
      );
    }

    final directOk = await sendSmsDirectAndroid(number, body);
    if (directOk) {
      appLog.d('Android direct SMS send');
      return _outcome(
        device: true,
        relay: false,
        detail:
            'Device SMS request accepted for $number ✓ (carrier delivery not confirmed)',
      );
    }

    return _outcome(
      device: false,
      relay: false,
      detail:
          'SMS not sent — configure SMS_DISPATCH_URL + SMS_DISPATCH_ANON_KEY or allow SEND_SMS.',
    );
  }

  static String _composeBody(String payload, double? lat, double? lng) {
    IndiaEmergencyRoute? route;
    if (lat != null && lng != null && coordinatesRoughlyInIndia(lat, lng)) {
      route = resolveIndiaEmergencyRoute(lat, lng);
    }
    final loc = (lat != null && lng != null)
        ? 'LOC ${lat.toStringAsFixed(5)},${lng.toStringAsFixed(5)} '
        : '';
    final st = route != null
        ? 'STATE ${route.stateCode} ${route.stateName} '
        : '';
    const maxPayload = 220;
    final p = payload.length > maxPayload
        ? '${payload.substring(0, maxPayload)}…'
        : payload;
    return 'RoadSOS $st$loc$p';
  }

  static Future<void> _postIndiaErssIngest(
    String url,
    String payload,
    double lat,
    double lng,
  ) async {
    final route = resolveIndiaEmergencyRoute(lat, lng);
    try {
      final headers = <String, String>{'Content-Type': 'application/json'};
      final key = dotenv.env['INDIA_ERSS_API_KEY']?.trim();
      if (key != null && key.isNotEmpty) {
        headers['Authorization'] = 'Bearer $key';
      }
      final response = await http
          .post(
            Uri.parse(url),
            headers: headers,
            body: jsonEncode(<String, dynamic>{
              'schema': 'roadsos.india_erss.v1',
              'latitude': lat,
              'longitude': lng,
              'payload': payload,
              if (route != null) ...<String, dynamic>{
                'state_code': route.stateCode,
                'state_name': route.stateName,
                'ambulance_number': route.ambulanceNumber,
              },
            }),
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        appLog.d('India ERSS ingest accepted');
      } else {
        appLog.w('India ERSS ingest HTTP ${response.statusCode}');
      }
    } on Object catch (e, st) {
      appLog.w('India ERSS ingest failed', error: e, stackTrace: st);
    }
  }

  static Future<bool> _postJson(String url, Map<String, dynamic> body) async {
    try {
      final headers = <String, String>{'Content-Type': 'application/json'};
      final secret = dotenv.env['SMS_DISPATCH_ANON_KEY']?.trim();
      if (secret != null && secret.isNotEmpty) {
        headers['Authorization'] = 'Bearer $secret';
      }
      final response = await http
          .post(Uri.parse(url), headers: headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 15));
      return response.statusCode >= 200 && response.statusCode < 300;
    } on Object catch (e, st) {
      appLog.w('SMS HTTP dispatch error', error: e, stackTrace: st);
      return false;
    }
  }
}
