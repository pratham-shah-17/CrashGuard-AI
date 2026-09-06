import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import 'ai_triage_service.dart';
import 'location_service.dart';
import 'sms_direct_send.dart';
import 'user_profile_service.dart';
import '../logging/app_log.dart';

final familyTrackingServiceProvider = Provider<FamilyTrackingService>((ref) {
  return FamilyTrackingService(ref);
});

/// Registers an ephemeral tracking token in Supabase and optionally SMSes the profile contact.
///
/// Browser opens `GET /functions/v1/family-track?t=<token>` (deploy Edge Function + migration).
class FamilyTrackingService {
  FamilyTrackingService(this._ref);

  final Ref _ref;

  /// Best-effort digit sequence for SMS (India-friendly).
  static String? normalizePhoneDigits(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 10) return null;
    if (digits.length == 10) return digits;
    if (digits.length == 11 && digits.startsWith('0')) {
      return digits.substring(1);
    }
    if (digits.length >= 12 && digits.startsWith('91')) {
      return digits.substring(digits.length - 10);
    }
    return digits.length > 10 ? digits.substring(digits.length - 10) : digits;
  }

  Future<({bool ok, String detail})> registerAndNotifyContact({
    required String incidentId,
    required LocationFix location,
    required TriageResult triage,
  }) async {
    if (kIsWeb || !isSupabaseSdkInitialized) {
      return (
        ok: false,
        detail: 'Family link needs Supabase on mobile — skipped.',
      );
    }

    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) {
      return (
        ok: false,
        detail: 'No auth session — sign in anonymously for family link.',
      );
    }

    final baseUrl = dotenv.env['SUPABASE_URL']?.trim() ?? '';
    if (baseUrl.isEmpty) {
      return (ok: false, detail: 'SUPABASE_URL not configured.');
    }

    final token = const Uuid().v4();
    final rawSummary =
        '${triage.functionCall} · sev ${triage.severityLevel} · ${triage.compressedPayload}';
    final triageSummary = rawSummary.length > 1200
        ? '${rawSummary.substring(0, 1197)}…'
        : rawSummary;

    final expiresAt = DateTime.now().toUtc().add(const Duration(hours: 24));

    try {
      await client.from('incident_live_links').insert({
        'user_id': user.id,
        'incident_id': incidentId,
        'token': token,
        'latitude': location.latitude,
        'longitude': location.longitude,
        'accuracy_m': location.accuracy,
        'triage_summary': triageSummary,
        'severity': triage.severityLevel,
        'expires_at': expiresAt.toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    } on Object catch (e, st) {
      appLog.w('incident_live_links insert failed', error: e, stackTrace: st);
      return (
        ok: false,
        detail:
            'Could not create family link (apply migration + RLS). ${e.runtimeType}',
      );
    }

    final root = baseUrl.replaceAll(RegExp(r'/+$'), '');
    final trackingUrl =
        '$root/functions/v1/family-track?t=${Uri.encodeComponent(token)}';

    final profile = _ref.read(userProfileProvider);
    final contacts = profile.allEmergencyContacts;

    if (contacts.isEmpty) {
      return (
        ok: true,
        detail:
            'Family link active — add contacts in Medical profile to auto-SMS.',
      );
    }

    final trimmedName = profile.fullName.trim();
    final name = trimmedName.isEmpty ? 'RoadSOS user' : trimmedName;
    final body =
        'RoadSOS: $name needs help. Live location & triage: $trackingUrl '
        '(updates if app online; expires 24h).';

    int sentCount = 0;
    if (!kIsWeb && Platform.isAndroid) {
      for (final rawPhone in contacts) {
        final phone = normalizePhoneDigits(rawPhone);
        if (phone != null && phone.isNotEmpty) {
          final sent = await sendSmsDirectAndroid(phone, body);
          if (sent) sentCount++;
        }
      }

      if (sentCount > 0) {
        return (
          ok: true,
          detail: 'Family link sent SMS to $sentCount contact(s) ✓',
        );
      }
      return (
        ok: true,
        detail:
            'Link ready — SMS failed for all contacts (permission?). Open link: $trackingUrl',
      );
    }

    return (
      ok: true,
      detail:
          'Family link ready — iOS cannot auto-SMS contact; share: $trackingUrl',
    );
  }
}
