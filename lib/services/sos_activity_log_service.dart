import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../logging/app_log.dart';
import '../models/sos_activity_record.dart';

const _maxRecords = 30;

/// Persists SOS dispatch summaries for trust UI and post-incident documentation (e.g. insurance).
class SosActivityLogService {
  SosActivityLogService._();
  static final SosActivityLogService instance = SosActivityLogService._();

  static const _storage = FlutterSecureStorage();
  static const _key = 'roadsos.sos_activity_history.v2';

  Future<List<SosActivityRecord>> loadHistory() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => SosActivityRecord.fromJson(e as Map<String, dynamic>))
          .toList();
    } on Object catch (e, st) {
      appLog.w('Activity log parse failed', error: e, stackTrace: st);
      return [];
    }
  }

  Future<void> append(SosActivityRecord record) async {
    try {
      final existing = await loadHistory();
      final next = [record, ...existing];
      final trimmed = next.length > _maxRecords
          ? next.sublist(0, _maxRecords)
          : next;
      await _storage.write(
        key: _key,
        value: jsonEncode(trimmed.map((e) => e.toJson()).toList()),
      );
    } on Object catch (e, st) {
      appLog.w('Activity log append failed', error: e, stackTrace: st);
    }
  }
}
