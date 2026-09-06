import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../logging/app_log.dart';

/// Phase 6 — Bluetooth vehicle disconnection monitor.
///
/// In a moving vehicle, the phone is typically connected to the car's
/// infotainment system (A2DP for audio / HFP for calls). A sudden loss
/// of that connection while the vehicle is travelling at speed is a
/// contextual signal correlated with collisions.
///
/// This service polls [FlutterBluePlus.connectedDevices] every 5 seconds
/// and compares the list against the previous snapshot. When a device
/// disappears (disconnect) AND the last known GPS speed is above
/// [_vehicleSpeedThresholdKmh], it records a [BluetoothDisconnectEvent]
/// timestamped for 30 seconds. The [CrashConfidenceEngine] reads
/// [recentDisconnect] to add +0.08 to the crash score.
///
/// False-positive guard:
///   - Only signals if GPS speed was ≥ 20 km/h at disconnect time.
///   - Only signals if BT was previously connected for ≥ 8 seconds
///     (avoids spurious connect/disconnect noise at app start).
///   - Signal expires after 30 seconds.
///
/// Privacy: no device names or MAC addresses are logged or transmitted.
/// The service only records the *fact* of a disconnection event.
class BluetoothVehicleMonitor {
  static const double _vehicleSpeedThresholdKmh = 20.0;
  static const Duration _connectStabilityMin = Duration(seconds: 8);
  static const Duration _signalTtl = Duration(seconds: 30);
  static const Duration _pollInterval = Duration(seconds: 5);

  Timer? _pollTimer;
  StreamSubscription<Position>? _positionSub;

  // Connected device IDs from previous poll cycle.
  Set<String> _prevConnected = {};
  // Timestamp when each device became connected (for stability gate).
  final Map<String, DateTime> _connectedSince = {};

  double _lastSpeedKmh = 0.0;
  DateTime? _disconnectAt;

  /// True if a vehicle-speed Bluetooth disconnection occurred within the last
  /// [_signalTtl] seconds. Read by [CrashConfidenceEngine].
  bool get recentDisconnect {
    if (_disconnectAt == null) return false;
    return DateTime.now().difference(_disconnectAt!) < _signalTtl;
  }

  void startMonitoring() {
    stopMonitoring();
    _startGpsSpeedTracking();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _poll());
    // Seed initial connected set immediately.
    _poll();
  }

  void stopMonitoring() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _positionSub?.cancel();
    _positionSub = null;
  }

  void _startGpsSpeedTracking() {
    try {
      _positionSub =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium,
              distanceFilter: 10,
            ),
          ).listen((p) {
            if (!p.speed.isNaN && p.speed >= 0) {
              _lastSpeedKmh = (p.speed * 3.6).clamp(0.0, 320.0);
            }
          }, onError: (Object _) {});
    } on Object catch (_) {}
  }

  void _poll() {
    List<BluetoothDevice> devices;
    try {
      devices = FlutterBluePlus.connectedDevices;
    } on Object catch (_) {
      return; // BT not available on this device.
    }

    final now = DateTime.now();
    final currentIds = devices.map((d) => d.remoteId.str).toSet();

    // Track newly connected devices for stability gate.
    for (final id in currentIds.difference(_prevConnected)) {
      _connectedSince[id] = now;
    }

    // Detect disconnections.
    for (final id in _prevConnected.difference(currentIds)) {
      final connectedAt = _connectedSince[id];
      final stable =
          connectedAt != null &&
          now.difference(connectedAt) >= _connectStabilityMin;

      if (stable && _lastSpeedKmh >= _vehicleSpeedThresholdKmh) {
        _disconnectAt = now;
        appLog.w(
          '[BTMonitor] Vehicle BT disconnect at ${_lastSpeedKmh.toStringAsFixed(0)} km/h '
          '— crash confidence +0.08 for 30s (device ID not logged)',
        );
      }

      _connectedSince.remove(id);
    }

    _prevConnected = currentIds;
  }

  void dispose() => stopMonitoring();
}

/// Non-autoDispose: must track BT connections for the full driving session.
final bluetoothVehicleMonitorProvider = Provider<BluetoothVehicleMonitor>((
  ref,
) {
  final svc = BluetoothVehicleMonitor();
  svc.startMonitoring();
  ref.onDispose(svc.dispose);
  return svc;
});
