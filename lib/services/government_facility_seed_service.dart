import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:powersync/powersync.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../logging/app_log.dart';

/// Imports bundled NHM / Ayushman-style government facility rows into SQLite.
/// Live OSM-derived rows are replicated from Supabase (Edge cron → Postgres → PowerSync).
class GovernmentFacilitySeedService {
  static const _prefsKeyImportedVersion = 'government_facilities_seed_version';
  static const assetPath = 'assets/data/government_facilities_seed.json';

  Future<void> importBundledSeedIfNeeded(PowerSyncDatabase db) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = await rootBundle.loadString(assetPath);
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final version = decoded['version'];
    final v = version is int ? version : int.tryParse('$version') ?? 0;

    final last = prefs.getInt(_prefsKeyImportedVersion) ?? -1;
    if (last >= v) return;

    final list = decoded['facilities'] as List<dynamic>? ?? [];
    var n = 0;
    final batchParameters = <List<Object?>>[];
    for (final item in list) {
      if (item is! Map<String, dynamic>) continue;
      final row = Map<String, dynamic>.from(item);
      final id = row['id']?.toString() ?? '';
      if (id.isEmpty) continue;

      batchParameters.add([
        id,
        row['name'] ?? 'Facility',
        row['type'] ?? 'hospital',
        (row['latitude'] as num).toDouble(),
        (row['longitude'] as num).toDouble(),
        row['contact_number'],
        row['capabilities'],
        row['data_source'] ?? 'gov',
        row['state_code'],
        row['district'],
      ]);
      n++;
    }

    if (batchParameters.isNotEmpty) {
      await db.executeBatch('''
        INSERT OR REPLACE INTO emergency_facilities
          (id, name, type, latitude, longitude, contact_number, capabilities, data_source, state_code, district)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''', batchParameters);
    }

    await prefs.setInt(_prefsKeyImportedVersion, v);
    appLog.d('GovSeed: imported $n government facility rows (seed v$v)');
  }
}
