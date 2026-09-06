import 'package:shared_preferences/shared_preferences.dart';

/// DPDP Act, 2023 — explicit consent + optional extended cloud retention flag.
class PrivacyConsentService {
  PrivacyConsentService._();

  static const _kConsentAt = 'dpdp_consent_accepted_at_iso8601';
  static const _kExtendedRetention = 'extended_cloud_retention_opt_in';

  /// `true` if user completed the first-launch consent flow.
  static Future<bool> hasConsent() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kConsentAt) != null;
  }

  static Future<void> recordConsent({
    required bool extendedCloudRetention,
  }) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kConsentAt, DateTime.now().toUtc().toIso8601String());
    await p.setBool(_kExtendedRetention, extendedCloudRetention);
  }

  static Future<bool> extendedCloudRetentionEnabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kExtendedRetention) ?? false;
  }

  static Future<void> setExtendedCloudRetention(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kExtendedRetention, value);
  }

  /// Convenience: best-effort read that never throws.
  static Future<bool> extendedRetentionForUploads() async {
    try {
      return await extendedCloudRetentionEnabled();
    } on Object catch (_) {
      return false;
    }
  }
}
