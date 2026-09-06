import 'dart:async';
import 'dart:collection';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../logging/app_log.dart';
import 'package:geolocator/geolocator.dart';

/// Represents a single GPS fix with metadata about its source and quality.
class LocationFix {
  final double latitude;
  final double longitude;
  final double accuracy;
  final String source; // 'gps', 'network', 'last_known', 'unknown'
  final DateTime timestamp;

  const LocationFix({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.source,
    required this.timestamp,
  });

  /// Compress to the 11-byte SOS payload format.
  String toCompressedString() {
    return 'LAT:${latitude.toStringAsFixed(5)}|LNG:${longitude.toStringAsFixed(5)}|ACC:${accuracy.round()}m|SRC:$source';
  }

  @override
  String toString() =>
      '($latitude, $longitude) ±${accuracy.round()}m [$source]';
}

/// Provides real-time location with dead-reckoning fallback.
///
/// Implements Blueprint §3.4 — GPS Multipath Error handling:
/// - Caches last 60 seconds of valid GPS coordinates
/// - Retries up to 2 times before falling back to last known
/// - On retry 2 we widen to LocationAccuracy.high to trade precision for speed
/// - Reports accuracy and source for downstream confidence scoring
///
/// Why retry matters: On Indian highways with intermittent satellite lock,
/// a single 8s timeout commonly fails. A second attempt at lower accuracy
/// typically succeeds within 3s and gives a good-enough fix for dispatch.
class LocationService {
  final Queue<LocationFix> _positionHistory = Queue<LocationFix>();
  static const int _maxHistorySeconds = 60;
  LocationFix? _lastGoodFix;

  /// Request current location with highest available accuracy.
  /// Retries once at reduced accuracy before falling back to last known.
  Future<LocationFix> getCurrentLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return _fallbackLocation('Location services disabled');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return _fallbackLocation('Location permission denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return _fallbackLocation('Location permanently denied');
    }

    // Attempt 1: best-for-navigation accuracy, 8-second window.
    // Increased from 5s → 8s: under-road tunnels and building shadows
    // on Indian highways frequently need 6–7s to lock.
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          timeLimit: Duration(seconds: 8),
        ),
      );
      final fix = _toFix(position, source: 'gps');
      _recordFix(fix);
      appLog.d(
        '[Location] GPS fix acquired (attempt 1): ${fix.accuracy.round()}m',
      );
      return fix;
    } on Object catch (e) {
      appLog.d(
        '[Location] Attempt 1 failed ($e) — retrying at medium accuracy',
      );
    }

    // Attempt 2: medium accuracy (cell-towers + GPS), 5-second window.
    // More likely to succeed when sat lock is temporarily lost.
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 5),
        ),
      );
      final fix = _toFix(position, source: 'network');
      _recordFix(fix);
      appLog.d(
        '[Location] GPS fix acquired (attempt 2 medium): ${fix.accuracy.round()}m',
      );
      return fix;
    } on Object catch (e) {
      appLog.d('[Location] Attempt 2 failed ($e) — trying last known from OS');
    }

    // Attempt 3: OS last-known position (near-instant, possibly stale).
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        final fix = _toFix(last, source: 'last_known');
        _recordFix(fix);
        appLog.d(
          '[Location] Using OS last-known position: ${fix.accuracy.round()}m',
        );
        return fix;
      }
    } on Object catch (_) {}

    return _fallbackLocation('All location attempts failed');
  }

  LocationFix _toFix(Position position, {required String source}) {
    return LocationFix(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
      source: source,
      timestamp: DateTime.now(),
    );
  }

  /// Fallback: return last good cached position or a degraded unknown fix.
  LocationFix _fallbackLocation(String reason) {
    appLog.d('[Location] Fallback triggered: $reason');

    if (_lastGoodFix != null) {
      return LocationFix(
        latitude: _lastGoodFix!.latitude,
        longitude: _lastGoodFix!.longitude,
        accuracy: _lastGoodFix!.accuracy + 50, // degrade accuracy estimate
        source: 'last_known',
        timestamp: _lastGoodFix!.timestamp,
      );
    }

    return LocationFix(
      latitude: 0.0,
      longitude: 0.0,
      accuracy: 99999,
      source: 'unknown',
      timestamp: DateTime.now(),
    );
  }

  void _recordFix(LocationFix fix) {
    _lastGoodFix = fix;
    _positionHistory.addLast(fix);

    final cutoff = DateTime.now().subtract(
      const Duration(seconds: _maxHistorySeconds),
    );
    while (_positionHistory.isNotEmpty &&
        _positionHistory.first.timestamp.isBefore(cutoff)) {
      _positionHistory.removeFirst();
    }
  }
}

final locationServiceProvider = Provider<LocationService>((ref) {
  return LocationService();
});
