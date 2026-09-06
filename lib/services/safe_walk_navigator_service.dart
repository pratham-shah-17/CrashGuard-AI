import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../logging/app_log.dart';

/// Average walking speed in m/s (≈4.5 km/h — typical adult pace on a flat
/// urban path; matches WHO ambulatory-mobility figures used by city planning).
const double _kAvgWalkingMps = 1.25;

/// Maximum distance from the destination at which we declare "arrived" and
/// auto-end the Safe Walk. Tuned for GPS noise on Indian streets where
/// 15-30 m fixes are typical even with high-accuracy mode.
const double _kArrivalGeofenceMeters = 30.0;

/// A single OSRM turn-by-turn step (greatly trimmed to the fields we care
/// about). Free public router at https://router.project-osrm.org — no key,
/// rate-limited but plenty for hackathon traffic; production would self-host.
class NavStep {
  const NavStep({
    required this.instruction,
    required this.distanceMeters,
    required this.maneuver,
    required this.location,
  });

  final String instruction;
  final double distanceMeters;
  final String maneuver;
  final LatLng location;
}

class SafeWalkNavState {
  const SafeWalkNavState({
    this.active = false,
    this.destinationName,
    this.destination,
    this.lastFix,
    this.route = const <LatLng>[],
    this.steps = const <NavStep>[],
    this.currentStepIndex = 0,
    this.bearingToDestinationDeg = 0,
    this.bearingToNextStepDeg = 0,
    this.distanceToDestinationMeters = 0,
    this.distanceToNextStepMeters = 0,
    this.estimatedSecondsRemaining = 0,
    this.deviceHeadingDeg = 0,
    this.lastSpokenInstruction,
    this.arrived = false,
    this.errorMessage,
    this.routingDegraded = false,
  });

  final bool active;
  final String? destinationName;
  final LatLng? destination;
  final LatLng? lastFix;
  final List<LatLng> route;
  final List<NavStep> steps;
  final int currentStepIndex;
  final double bearingToDestinationDeg;
  final double bearingToNextStepDeg;
  final double distanceToDestinationMeters;
  final double distanceToNextStepMeters;
  final int estimatedSecondsRemaining;
  final double deviceHeadingDeg;
  final String? lastSpokenInstruction;
  final bool arrived;
  final String? errorMessage;

  /// True when we fell back to straight-line bearing because the OSRM router
  /// did not respond (offline / rate-limited / API down).
  final bool routingDegraded;

  SafeWalkNavState copyWith({
    bool? active,
    Object? destinationName = _sentinel,
    Object? destination = _sentinel,
    Object? lastFix = _sentinel,
    List<LatLng>? route,
    List<NavStep>? steps,
    int? currentStepIndex,
    double? bearingToDestinationDeg,
    double? bearingToNextStepDeg,
    double? distanceToDestinationMeters,
    double? distanceToNextStepMeters,
    int? estimatedSecondsRemaining,
    double? deviceHeadingDeg,
    Object? lastSpokenInstruction = _sentinel,
    bool? arrived,
    Object? errorMessage = _sentinel,
    bool? routingDegraded,
  }) {
    return SafeWalkNavState(
      active: active ?? this.active,
      destinationName: identical(destinationName, _sentinel)
          ? this.destinationName
          : destinationName as String?,
      destination: identical(destination, _sentinel)
          ? this.destination
          : destination as LatLng?,
      lastFix: identical(lastFix, _sentinel)
          ? this.lastFix
          : lastFix as LatLng?,
      route: route ?? this.route,
      steps: steps ?? this.steps,
      currentStepIndex: currentStepIndex ?? this.currentStepIndex,
      bearingToDestinationDeg:
          bearingToDestinationDeg ?? this.bearingToDestinationDeg,
      bearingToNextStepDeg: bearingToNextStepDeg ?? this.bearingToNextStepDeg,
      distanceToDestinationMeters:
          distanceToDestinationMeters ?? this.distanceToDestinationMeters,
      distanceToNextStepMeters:
          distanceToNextStepMeters ?? this.distanceToNextStepMeters,
      estimatedSecondsRemaining:
          estimatedSecondsRemaining ?? this.estimatedSecondsRemaining,
      deviceHeadingDeg: deviceHeadingDeg ?? this.deviceHeadingDeg,
      lastSpokenInstruction: identical(lastSpokenInstruction, _sentinel)
          ? this.lastSpokenInstruction
          : lastSpokenInstruction as String?,
      arrived: arrived ?? this.arrived,
      errorMessage: identical(errorMessage, _sentinel)
          ? this.errorMessage
          : errorMessage as String?,
      routingDegraded: routingDegraded ?? this.routingDegraded,
    );
  }

  static const _sentinel = Object();
}

/// Real-time walking navigator backing the Safe Walk Navigator screen.
///
/// Responsibilities:
///   * Pull a foot-routing polyline + turn list from OSRM
///     (https://router.project-osrm.org — free, no key) for visual + voice.
///   * Listen to live GPS via geolocator, recompute distance + bearing each
///     fix, advance the current step when the user passes within 25 m.
///   * Detect arrival via a 30 m geofence and auto-end the walk.
///   * Surface per-fix state to the screen (compass arrow uses
///     [bearingToDestinationDeg] - [deviceHeadingDeg] for the rotation).
///
/// Fail-soft behaviour when OSRM is unreachable: still publishes a straight-
/// line bearing + Haversine distance so the AirTag-style arrow + ETA still
/// work offline; UI surfaces "routing offline" hint via [routingDegraded].
class SafeWalkNavigatorService extends StateNotifier<SafeWalkNavState> {
  SafeWalkNavigatorService() : super(const SafeWalkNavState());

  StreamSubscription<Position>? _posSub;
  Timer? _spokenInstructionDebounce;

  /// Start walking to [destination] (lat/lng pair already geocoded by the
  /// caller — the destination autocomplete in the start dialog uses
  /// Nominatim). [destinationName] is whatever the user picked from the
  /// suggestion list — used for TTS prompts + the overlay label.
  Future<void> start({
    required LatLng destination,
    required String destinationName,
  }) async {
    await stop();
    state = SafeWalkNavState(
      active: true,
      destination: destination,
      destinationName: destinationName,
    );

    final start = await _bestEffortFix();
    if (start != null) {
      state = state.copyWith(lastFix: start);
      await _pullRoute(start, destination);
      _recompute(start);
    }

    _posSub =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: 5,
          ),
        ).listen(
          (pos) {
            final fix = LatLng(pos.latitude, pos.longitude);
            state = state.copyWith(
              lastFix: fix,
              deviceHeadingDeg: pos.heading.isNaN || pos.heading < 0
                  ? state.deviceHeadingDeg
                  : pos.heading,
            );
            _recompute(fix);
          },
          onError: (e) {
            appLog.d('[SafeWalkNav] position stream error: $e');
          },
        );
  }

  Future<void> stop() async {
    await _posSub?.cancel();
    _posSub = null;
    _spokenInstructionDebounce?.cancel();
    _spokenInstructionDebounce = null;
    state = const SafeWalkNavState();
  }

  /// Called by the compass plugin in the UI layer (the navigator service is
  /// pure Dart + has no platform sensors of its own). Magnetic heading in
  /// degrees clockwise from North.
  void updateDeviceHeading(double heading) {
    if (!state.active) return;
    if (heading.isNaN) return;
    final h = ((heading % 360) + 360) % 360;
    state = state.copyWith(deviceHeadingDeg: h);
  }

  // ── Internals ────────────────────────────────────────────────────────────

  Future<LatLng?> _bestEffortFix() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 5),
        ),
      );
      return LatLng(pos.latitude, pos.longitude);
    } on Object catch (_) {
      try {
        final pos = await Geolocator.getLastKnownPosition();
        if (pos != null) return LatLng(pos.latitude, pos.longitude);
      } on Object catch (_) {}
      return null;
    }
  }

  Future<void> _pullRoute(LatLng a, LatLng b) async {
    try {
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/foot/'
        '${a.longitude},${a.latitude};${b.longitude},${b.latitude}'
        '?overview=full&geometries=geojson&steps=true',
      );
      final resp = await http
          .get(url, headers: const {'User-Agent': 'RoadSOS/1.0'})
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) {
        throw HttpException('OSRM HTTP ${resp.statusCode}');
      }
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final routes = (body['routes'] as List?) ?? const [];
      if (routes.isEmpty) throw const HttpException('OSRM returned no routes');
      final route = routes.first as Map<String, dynamic>;
      final coords =
          ((route['geometry'] as Map<String, dynamic>)['coordinates'] as List)
              .cast<List>()
              .map(
                (c) =>
                    LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
              )
              .toList();

      final legs = (route['legs'] as List?) ?? const [];
      final steps = <NavStep>[];
      for (final leg in legs.cast<Map<String, dynamic>>()) {
        for (final s in (leg['steps'] as List).cast<Map<String, dynamic>>()) {
          final maneuver = s['maneuver'] as Map<String, dynamic>;
          final loc = (maneuver['location'] as List).cast<num>();
          final type = (maneuver['type'] as String?) ?? 'turn';
          final mod = (maneuver['modifier'] as String?) ?? '';
          final road = (s['name'] as String?)?.trim() ?? '';
          steps.add(
            NavStep(
              instruction: _phraseFor(type, mod, road),
              distanceMeters: ((s['distance'] as num?) ?? 0).toDouble(),
              maneuver: type,
              location: LatLng(loc[1].toDouble(), loc[0].toDouble()),
            ),
          );
        }
      }

      state = state.copyWith(
        route: coords,
        steps: steps,
        currentStepIndex: 0,
        routingDegraded: false,
      );
    } on Object catch (e, st) {
      appLog.d(
        '[SafeWalkNav] OSRM unreachable, falling back to bearing-only',
        stackTrace: st,
      );
      state = state.copyWith(
        route: const <LatLng>[],
        steps: const <NavStep>[],
        currentStepIndex: 0,
        routingDegraded: true,
      );
    }
  }

  void _recompute(LatLng me) {
    final dest = state.destination;
    if (dest == null) return;

    final dist = _haversineMeters(me, dest);
    final brg = _bearingDeg(me, dest);
    final etaSec = (dist / _kAvgWalkingMps).round();

    // Did we arrive?
    if (dist <= _kArrivalGeofenceMeters && !state.arrived) {
      state = state.copyWith(
        arrived: true,
        distanceToDestinationMeters: dist,
        bearingToDestinationDeg: brg,
        estimatedSecondsRemaining: 0,
      );
      // Caller (overlay screen) reacts to `arrived` and ends the walk.
      return;
    }

    // Advance step pointer when within 25m of the next maneuver waypoint.
    var stepIdx = state.currentStepIndex;
    double distToNext = 0;
    double brgToNext = brg;
    String? newlyEntered;
    if (state.steps.isNotEmpty) {
      while (stepIdx < state.steps.length - 1 &&
          _haversineMeters(me, state.steps[stepIdx].location) <= 25) {
        stepIdx++;
        newlyEntered = state.steps[stepIdx].instruction;
      }
      distToNext = _haversineMeters(me, state.steps[stepIdx].location);
      brgToNext = _bearingDeg(me, state.steps[stepIdx].location);
    }

    state = state.copyWith(
      distanceToDestinationMeters: dist,
      bearingToDestinationDeg: brg,
      distanceToNextStepMeters: distToNext,
      bearingToNextStepDeg: brgToNext,
      estimatedSecondsRemaining: etaSec,
      currentStepIndex: stepIdx,
      lastSpokenInstruction: newlyEntered ?? state.lastSpokenInstruction,
    );
  }

  String _phraseFor(String type, String mod, String road) {
    final onRoad = road.isEmpty ? '' : ' onto $road';
    switch (type) {
      case 'depart':
        return road.isEmpty ? 'Start walking' : 'Start walking on $road';
      case 'arrive':
        return road.isEmpty ? 'Arrive at your destination' : 'Arrive at $road';
      case 'turn':
        if (mod.isEmpty) return 'Turn$onRoad';
        return 'Turn $mod$onRoad';
      case 'continue':
        return 'Continue straight$onRoad';
      case 'roundabout':
      case 'rotary':
        return 'Take the roundabout$onRoad';
      case 'fork':
        return 'Keep $mod at the fork$onRoad';
      case 'merge':
        return 'Merge $mod$onRoad';
      case 'new name':
        return road.isEmpty ? 'Continue' : 'Continue on $road';
      default:
        return mod.isEmpty ? 'Continue' : 'Go $mod$onRoad';
    }
  }
}

double _haversineMeters(LatLng a, LatLng b) {
  const r = 6371000.0;
  final lat1 = a.latitude * math.pi / 180;
  final lat2 = b.latitude * math.pi / 180;
  final dlat = (b.latitude - a.latitude) * math.pi / 180;
  final dlon = (b.longitude - a.longitude) * math.pi / 180;
  final h =
      math.sin(dlat / 2) * math.sin(dlat / 2) +
      math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2) * math.sin(dlon / 2);
  return 2 * r * math.asin(math.min(1.0, math.sqrt(h)));
}

double _bearingDeg(LatLng a, LatLng b) {
  final lat1 = a.latitude * math.pi / 180;
  final lat2 = b.latitude * math.pi / 180;
  final dlon = (b.longitude - a.longitude) * math.pi / 180;
  final y = math.sin(dlon) * math.cos(lat2);
  final x =
      math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(dlon);
  final theta = math.atan2(y, x);
  final deg = (theta * 180 / math.pi + 360) % 360;
  return deg;
}

class HttpException implements Exception {
  const HttpException(this.message);
  final String message;
  @override
  String toString() => 'HttpException: $message';
}

final safeWalkNavigatorProvider =
    StateNotifierProvider<SafeWalkNavigatorService, SafeWalkNavState>((ref) {
      return SafeWalkNavigatorService();
    });
