import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../logging/app_log.dart';
import '../services/remote_crash_config.dart';

/// Bootstraps runtime configuration without bundling secrets as app assets.
///
/// Production: prefer `--dart-define=KEY=VALUE` (and friends) via CI/CD.
/// Dev: place a non-committed `.env` file in the project root when running `flutter run` locally.
///
/// Key architecture:
/// - GEMMA_API_KEY is set as a Supabase Edge Function secret (never on the client).
/// - TWILIO_* credentials are set as Supabase Edge Function secrets.
/// - SUPABASE_URL + SUPABASE_ANON_KEY are the only credentials on the mobile client.
/// - Crash thresholds are fetched live from the `crash_config` Supabase table
///   via [RemoteCrashConfig] — no app release needed to tune sensitivity.
class RuntimeConfig {
  RuntimeConfig._();

  static Future<void> bootstrap() async {
    try {
      dotenv.env.clear();
    } on Object catch (_) {}

    if (!kReleaseMode) {
      try {
        await dotenv.load(fileName: '.env');
        appLog.i('Loaded local .env for development');
      } on Object catch (_) {}
    }

    // ── Backend / cloud ────────────────────────────────────────────────────
    _setIfDefined('SUPABASE_URL');
    _setIfDefined('SUPABASE_ANON_KEY');
    _setIfDefined('POWERSYNC_URL');

    // ── SMS dispatch ───────────────────────────────────────────────────────
    _setIfDefined('SMS_DISPATCH_URL');
    _setIfDefined('SMS_DISPATCH_ANON_KEY');
    _setIfDefined('SMS_RELAY_COUNTS_AS_PRIMARY_DISPATCH');

    // ── India-specific routing ─────────────────────────────────────────────
    _setIfDefined('INDIA_SOS_DISPATCH_URL');
    _setIfDefined('INDIA_ERSS_API_URL');
    _setIfDefined('INDIA_ERSS_API_KEY');
    _setIfDefined('INDIA_EMERGENCY_USSD');
    _setIfDefined('INDIA_AUTO_DIAL_AMBULANCE');

    // ── Emergency number overrides ─────────────────────────────────────────
    _setIfDefined('EMERGENCY_NUMBER_OVERRIDE');
    _setIfDefined('EMERGENCY_NUMBER_FALLBACK');

    // ── Map ────────────────────────────────────────────────────────────────
    _setIfDefined('MAP_TILE_URL_TEMPLATE');

    // ── Connectivity-aware triage ──────────────────────────────────────────
    // Set to 'false' to always attempt Tier 1 cloud even when offline probe says no.
    _setIfDefined('CONNECTIVITY_AWARE_TRIAGE');

    // ── Remote crash thresholds — Phase 1 (cache only) ────────────────────
    // Loads the last persisted threshold values and geofence regions from
    // SharedPreferences so CrashTuning is ready before the first GPS event.
    // Does NOT touch the network. Phase 2 (Supabase fetch) happens in main()
    // after bootstrapSupabaseAuth() completes.
    await RemoteCrashConfig.instance.loadCachedValues();
  }

  static void _setIfDefined(String key) {
    final value = _readDefine(key);
    if (value == null || value.trim().isEmpty) return;
    dotenv.env[key] = value.trim();
  }

  static String? _readDefine(String key) {
    switch (key) {
      case 'SUPABASE_URL':
        return const String.fromEnvironment('SUPABASE_URL');
      case 'SUPABASE_ANON_KEY':
        return const String.fromEnvironment('SUPABASE_ANON_KEY');
      case 'POWERSYNC_URL':
        return const String.fromEnvironment('POWERSYNC_URL');
      case 'SMS_DISPATCH_URL':
        return const String.fromEnvironment('SMS_DISPATCH_URL');
      case 'SMS_DISPATCH_ANON_KEY':
        return const String.fromEnvironment('SMS_DISPATCH_ANON_KEY');
      case 'SMS_RELAY_COUNTS_AS_PRIMARY_DISPATCH':
        return const String.fromEnvironment(
          'SMS_RELAY_COUNTS_AS_PRIMARY_DISPATCH',
        );
      case 'INDIA_SOS_DISPATCH_URL':
        return const String.fromEnvironment('INDIA_SOS_DISPATCH_URL');
      case 'INDIA_ERSS_API_URL':
        return const String.fromEnvironment('INDIA_ERSS_API_URL');
      case 'INDIA_ERSS_API_KEY':
        return const String.fromEnvironment('INDIA_ERSS_API_KEY');
      case 'INDIA_EMERGENCY_USSD':
        return const String.fromEnvironment('INDIA_EMERGENCY_USSD');
      case 'INDIA_AUTO_DIAL_AMBULANCE':
        return const String.fromEnvironment('INDIA_AUTO_DIAL_AMBULANCE');
      case 'EMERGENCY_NUMBER_OVERRIDE':
        return const String.fromEnvironment('EMERGENCY_NUMBER_OVERRIDE');
      case 'EMERGENCY_NUMBER_FALLBACK':
        return const String.fromEnvironment('EMERGENCY_NUMBER_FALLBACK');
      case 'MAP_TILE_URL_TEMPLATE':
        return const String.fromEnvironment('MAP_TILE_URL_TEMPLATE');
      // Connectivity
      case 'CONNECTIVITY_AWARE_TRIAGE':
        return const String.fromEnvironment('CONNECTIVITY_AWARE_TRIAGE');
    }
    return null;
  }
}
