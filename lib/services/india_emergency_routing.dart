import 'package:latlong2/latlong.dart';

/// Offline-friendly India emergency routing from GPS.
///
/// Uses nearest state/UT centroid (Haversine via [Distance]). Border regions may
/// map to an adjacent state — for production accuracy, pair with server-side
/// reverse geocoding when online.
///
/// **Parallel dispatch channels (India):**
/// - **112** — national ERSS (MHA); SMS/voice per carrier integration.
/// - **108** — widely used state ambulance (EMRI/GVK-style); still critical in many rural belts.
/// - **100 / 101** — police / fire (legacy parallel lines; many routes merge into 112).
///
/// **Official ERSS / MHA API:** There is no stable public HTTPS spec in-repo; production
/// integrations are typically arranged via CDAC/MHA enrollment. Configure
/// `INDIA_ERSS_API_URL` + `INDIA_ERSS_API_KEY` and/or `INDIA_SOS_DISPATCH_URL` in `.env`.
class IndiaEmergencyRoute {
  const IndiaEmergencyRoute({
    required this.stateCode,
    required this.stateName,
    required this.nationalNumber,
    required this.ambulanceNumber,
    required this.policeNumber,
    required this.fireNumber,
  });

  /// ISO 3166-2 style, e.g. IN-KA.
  final String stateCode;
  final String stateName;

  /// ERSS single emergency number (voice/SMS per carrier).
  static const nationalErss = '112';

  final String nationalNumber;
  final String ambulanceNumber;
  final String policeNumber;
  final String fireNumber;
}

/// Rough bounding box for India (excludes Andaman overlap edge cases).
bool coordinatesRoughlyInIndia(double lat, double lng) {
  return lat >= 6.0 && lat <= 37.5 && lng >= 67.5 && lng <= 97.5;
}

/// Nearest state/UT by centroid distance. Returns null if outside India or too far from any centroid.
IndiaEmergencyRoute? resolveIndiaEmergencyRoute(double lat, double lng) {
  if (!coordinatesRoughlyInIndia(lat, lng)) return null;

  // Coarse state box overrides for border-sensitive metros where centroid routing is unreliable.
  // Keep this list tiny and explicit; for production accuracy use server-side reverse geocoding.
  final boxed = _resolveByCoarseBoxes(lat, lng);
  if (boxed != null) return boxed;

  const dist = Distance();
  final p = LatLng(lat, lng);

  _Centroid? best;
  var bestMeters = double.infinity;

  for (final c in _centroids) {
    final d = dist.as(LengthUnit.Meter, p, c.point);
    if (d < bestMeters) {
      bestMeters = d;
      best = c;
    }
  }

  if (best == null || bestMeters > 850000) return null;

  return IndiaEmergencyRoute(
    stateCode: best.code,
    stateName: best.name,
    nationalNumber: IndiaEmergencyRoute.nationalErss,
    ambulanceNumber: '108',
    policeNumber: '100',
    fireNumber: '101',
  );
}

IndiaEmergencyRoute? _resolveByCoarseBoxes(double lat, double lng) {
  // Bengaluru should never resolve to TN for common coordinates.
  // Karnataka (very rough): 11.5–18.6N, 74.0–78.9E
  if (lat >= 11.5 && lat <= 18.6 && lng >= 74.0 && lng <= 78.9) {
    return const IndiaEmergencyRoute(
      stateCode: 'IN-KA',
      stateName: 'Karnataka',
      nationalNumber: IndiaEmergencyRoute.nationalErss,
      ambulanceNumber: '108',
      policeNumber: '100',
      fireNumber: '101',
    );
  }
  // Tamil Nadu (rough): 8.0–13.6N, 76.0–80.6E
  if (lat >= 8.0 && lat <= 13.6 && lng >= 76.0 && lng <= 80.6) {
    return const IndiaEmergencyRoute(
      stateCode: 'IN-TN',
      stateName: 'Tamil Nadu',
      nationalNumber: IndiaEmergencyRoute.nationalErss,
      ambulanceNumber: '108',
      policeNumber: '100',
      fireNumber: '101',
    );
  }
  return null;
}

class _Centroid {
  const _Centroid(this.code, this.name, this.point);

  final String code;
  final String name;
  final LatLng point;
}

/// Approximate geographic centers (WGS84). Ambulance digits: most states use 108;
/// overrides only where commonly documented differently (still verify locally).
final List<_Centroid> _centroids = [
  _Centroid('IN-AP', 'Andhra Pradesh', LatLng(15.91, 79.74)),
  _Centroid('IN-AR', 'Arunachal Pradesh', LatLng(28.22, 94.73)),
  _Centroid('IN-AS', 'Assam', LatLng(26.14, 92.94)),
  _Centroid('IN-BR', 'Bihar', LatLng(25.10, 85.31)),
  _Centroid('IN-CT', 'Chhattisgarh', LatLng(21.28, 81.63)),
  _Centroid('IN-GA', 'Goa', LatLng(15.30, 74.12)),
  _Centroid('IN-GJ', 'Gujarat', LatLng(22.56, 71.19)),
  _Centroid('IN-HR', 'Haryana', LatLng(29.05, 76.08)),
  _Centroid('IN-HP', 'Himachal Pradesh', LatLng(31.10, 77.17)),
  _Centroid('IN-JH', 'Jharkhand', LatLng(23.61, 85.28)),
  _Centroid('IN-KA', 'Karnataka', LatLng(15.32, 75.72)),
  _Centroid('IN-KL', 'Kerala', LatLng(10.16, 76.64)),
  _Centroid('IN-MP', 'Madhya Pradesh', LatLng(23.47, 77.94)),
  _Centroid('IN-MH', 'Maharashtra', LatLng(19.75, 75.71)),
  _Centroid('IN-MN', 'Manipur', LatLng(24.66, 93.91)),
  _Centroid('IN-ML', 'Meghalaya', LatLng(25.57, 91.89)),
  _Centroid('IN-MZ', 'Mizoram', LatLng(23.73, 92.72)),
  _Centroid('IN-NL', 'Nagaland', LatLng(26.15, 94.56)),
  _Centroid('IN-OR', 'Odisha', LatLng(20.95, 85.10)),
  _Centroid('IN-PB', 'Punjab', LatLng(31.14, 75.34)),
  _Centroid('IN-RJ', 'Rajasthan', LatLng(27.02, 74.22)),
  _Centroid('IN-SK', 'Sikkim', LatLng(27.53, 88.51)),
  _Centroid('IN-TN', 'Tamil Nadu', LatLng(11.13, 78.66)),
  _Centroid('IN-TG', 'Telangana', LatLng(18.11, 79.55)),
  _Centroid('IN-TR', 'Tripura', LatLng(23.94, 91.29)),
  _Centroid('IN-UP', 'Uttar Pradesh', LatLng(26.85, 80.95)),
  _Centroid('IN-UT', 'Uttarakhand', LatLng(30.32, 79.02)),
  _Centroid('IN-WB', 'West Bengal', LatLng(22.99, 87.68)),
  _Centroid('IN-AN', 'Andaman and Nicobar Islands', LatLng(11.74, 92.66)),
  _Centroid('IN-CH', 'Chandigarh', LatLng(30.73, 76.78)),
  _Centroid(
    'IN-DN',
    'Dadra and Nagar Haveli and Daman and Diu',
    LatLng(20.27, 73.02),
  ),
  _Centroid('IN-DL', 'Delhi', LatLng(28.61, 77.20)),
  _Centroid('IN-JK', 'Jammu and Kashmir', LatLng(33.77, 76.57)),
  _Centroid('IN-LA', 'Ladakh', LatLng(34.15, 77.58)),
  _Centroid('IN-LD', 'Lakshadweep', LatLng(10.57, 72.64)),
  _Centroid('IN-PY', 'Puducherry', LatLng(11.94, 79.81)),
];
