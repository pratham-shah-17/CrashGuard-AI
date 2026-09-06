import 'dart:math' show cos, pi;
import 'package:flutter/foundation.dart' show kIsWeb;
import '../database/app_database.dart';
import '../models/facility.dart';

/// Queries pre-seeded + synced facilities around a point (bounding-box filter).
class FacilityQueryService {
  static const earthKmPerDeg = 111.0;

  Future<List<Facility>> queryNearby(
    double lat,
    double lon, {
    double radiusKm = 35,
    int limit = 80,
  }) async {
    if (kIsWeb || !isDatabaseInitialized) return [];

    final dLat = radiusKm / earthKmPerDeg;
    final cosLat = cos(lat * pi / 180).abs().clamp(0.2, 1.0);
    final dLon = radiusKm / (earthKmPerDeg * cosLat);

    final south = lat - dLat;
    final north = lat + dLat;
    final west = lon - dLon;
    final east = lon + dLon;

    final rows = await appDb.getAll(
      '''
      SELECT id, name, type, latitude, longitude, contact_number, capabilities, data_source
      FROM emergency_facilities
      WHERE latitude BETWEEN ? AND ?
        AND longitude BETWEEN ? AND ?
      LIMIT ?
      ''',
      [south, north, west, east, limit],
    );

    final out = <Facility>[];
    for (final r in rows) {
      final m = Map<String, dynamic>.from(r as Map);
      out.add(Facility.fromMap(m));
    }
    out.sort((a, b) {
      final da = _approxKm(lat, lon, a.latitude, a.longitude);
      final db = _approxKm(lat, lon, b.latitude, b.longitude);
      return da.compareTo(db);
    });
    return out;
  }

  double _approxKm(double lat1, double lon1, double lat2, double lon2) {
    final dx = (lon2 - lon1) * cos(lat1 * pi / 180) * earthKmPerDeg;
    final dy = (lat2 - lat1) * earthKmPerDeg;
    return dx * dx + dy * dy;
  }
}
