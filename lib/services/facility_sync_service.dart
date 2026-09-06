import '../logging/app_log.dart';

/// Facility rows are **not** fetched from Overpass on-device (that violates public API ToS at scale).
///
/// Server-side flow:
/// 1. Supabase Edge Function [sync-osm-facilities] runs on a schedule (cron) and queries Overpass once per job.
/// 2. Rows are upserted into Postgres `public.emergency_facilities`.
/// 3. PowerSync replicates to this app’s SQLite ([appDb]) for offline queries.
///
/// Call [syncLocalRegion] after location is known only to record a *hint* for operators/telemetry.
/// The app itself does not “force sync” facilities; facilities become available when:
/// - bundled seed has been imported, and/or
/// - PowerSync is configured + connected and replicating `emergency_facilities`.
class FacilitySyncService {
  FacilitySyncService();

  /// No longer performs HTTP to Overpass. Facilities arrive via seed + PowerSync from Supabase.
  ///
  /// Returns a status line suitable for debug UI (not a guarantee of facility freshness).
  Future<String> syncLocalRegion(
    double lat,
    double lon, {
    double radiusKm = 20.0,
  }) async {
    appLog.d(
      'Facility cache: server-side OSM ingest + PowerSync (no client Overpass). '
      'Region hint: ($lat,$lon) r=${radiusKm}km',
    );
    return 'Facility sync is cloud/seed-driven (no client Overpass).';
  }
}
