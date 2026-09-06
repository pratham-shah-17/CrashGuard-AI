import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

/// Extension point for **anonymized** crash / hazard density aligned with
/// Indian road-safety reporting ecosystems (e.g. MoRTH programmes such as
/// **iRASTE** — Intelligent Solutions for Road Safety through Technology and
/// Engineering).
///
/// There is **no stable public REST API** documented here; production use
/// requires outreach to MoRTH / NIC / programme office for **data-sharing MOU**
/// or approved aggregator endpoints. Until then, this service no-ops unless
/// `GOVERNMENT_CRASH_CONTRIBUTION_URL` is set.
///
/// Privacy: only coarse grid identifiers and aggregated counts — no user id,
/// phone, vehicle id, or exact GPS beyond the chosen grid resolution.
class IndiaGovernmentCrashContributionService {
  /// H3-like concept without adding a dependency: fixed-step grid from WGS84.
  /// Caller rounds lat/lon before sending (e.g. 3 decimals ~ 111 m).
  static ({String gridId, double lat, double lon}) anonymizedGridCell({
    required double latitude,
    required double longitude,
    int decimals = 3,
  }) {
    final rLat = double.parse(latitude.toStringAsFixed(decimals));
    final rLon = double.parse(longitude.toStringAsFixed(decimals));
    final gridId = '${rLat}_$rLon';
    return (gridId: gridId, lat: rLat, lon: rLon);
  }

  Future<void> submitHeatmapAggregates(List<CrashDensityCell> cells) async {
    final base = dotenv.maybeGet('GOVERNMENT_CRASH_CONTRIBUTION_URL')?.trim();
    if (base == null || base.isEmpty) return;
    if (cells.isEmpty) return;

    final uri = Uri.parse(base);
    final token = dotenv
        .maybeGet('GOVERNMENT_CRASH_CONTRIBUTION_TOKEN')
        ?.trim();

    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };

    final payload = jsonEncode({
      'schema_version': 1,
      'project': 'roadsos_anonymized_density',
      'cells': cells.map((c) => c.toJson()).toList(),
    });

    final response = await http
        .post(uri, headers: headers, body: payload)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpContributionException(
        'Contribution HTTP ${response.statusCode}: ${response.body}',
      );
    }
  }
}

class CrashDensityCell {
  CrashDensityCell({
    required this.gridId,
    required this.latitude,
    required this.longitude,
    required this.reportCount,
    required this.windowStartUtc,
    required this.windowEndUtc,
    required this.maxSeverityBucket,
  });

  final String gridId;
  final double latitude;
  final double longitude;
  final int reportCount;
  final String windowStartUtc;
  final String windowEndUtc;

  /// 1–5 coarse bucket; no free-text incident detail.
  final int maxSeverityBucket;

  Map<String, dynamic> toJson() => {
    'grid_id': gridId,
    'latitude': latitude,
    'longitude': longitude,
    'report_count': reportCount,
    'window_start_utc': windowStartUtc,
    'window_end_utc': windowEndUtc,
    'max_severity_bucket': maxSeverityBucket,
  };
}

class HttpContributionException implements Exception {
  HttpContributionException(this.message);
  final String message;

  @override
  String toString() => 'HttpContributionException: $message';
}
