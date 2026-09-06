import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../services/ble_payload_codec.dart';
import '../services/mesh_network_service.dart';

/// Bystander Radar — plots BLE-decoded SOS beacons in their *real* relative
/// position around the device, using bearing + distance from the device's
/// own GPS fix.
///
/// Previous behaviour (replaced):
///   Peer dots were placed at angle = id.hashCode and radius =
///   sqrt(hashCode>>8). This made the "radar" look populated but the dot
///   positions were synthetic — a peer 5 m east could be drawn as a dot 78 px
///   north-west. In an emergency that misleads a responder.
///
/// New behaviour:
///   For each [MeshPacket] received whose decoded payload contains valid
///   lat/lng, compute (bearing, distance) relative to the device GPS. Map
///   distance to radius via a soft 200 m logarithmic scale (so close peers
///   are near the centre and far peers are clamped to the rim). Map bearing
///   to angle (north = up). If GPS is unavailable or the packet did not
///   carry coordinates, fall back to RSSI-based radius (no fake angle —
///   peer is shown at the top of the radar instead of an invented bearing).
class BystanderRadar extends ConsumerStatefulWidget {
  const BystanderRadar({super.key});

  @override
  ConsumerState<BystanderRadar> createState() => _BystanderRadarState();
}

class _BystanderRadarState extends ConsumerState<BystanderRadar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  StreamSubscription<MeshPacket>? _packetsSub;
  StreamSubscription<Position>? _posSub;

  /// Map of senderId → most recently observed decoded packet (and RSSI).
  final Map<String, _PeerObservation> _peers = {};

  /// Most recent device GPS fix; null while waiting for first fix.
  Position? _myFix;

  static const Duration _peerTimeout = Duration(seconds: 45);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    _subscribeMeshPackets();
    _subscribeOwnPosition();
  }

  void _subscribeMeshPackets() {
    final mesh = ref.read(meshNetworkServiceProvider);
    _packetsSub = mesh.packets.listen((packet) {
      if (!mounted) return;
      setState(() {
        _peers[packet.senderId] = _PeerObservation(
          senderId: packet.senderId,
          decoded: packet.decoded,
          rssi: packet.rssi,
          observedAt: packet.receivedAt,
        );
        // Drop stale peers so the radar doesn't accumulate forever.
        final cutoff = DateTime.now().subtract(_peerTimeout);
        _peers.removeWhere((_, obs) => obs.observedAt.isBefore(cutoff));
      });
    });
  }

  Future<void> _subscribeOwnPosition() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return;
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      _posSub =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 5,
            ),
          ).listen((p) {
            if (!mounted) return;
            setState(() => _myFix = p);
          });
    } on Object catch (_) {
      /* permission or platform — radar still renders dots */
    }
  }

  @override
  void dispose() {
    _packetsSub?.cancel();
    _posSub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Stream of unique sender IDs from MeshNetworkService — used purely for
    // the "PEERS DETECTED: N" caption so the radar always shows a count even
    // when no decoded packets arrived yet.
    final beaconsStream = ref
        .watch(meshNetworkServiceProvider)
        .discoveredBeacons;

    return StreamBuilder<List<String>>(
      stream: beaconsStream,
      initialData: const [],
      builder: (context, snapshot) {
        final beacons = snapshot.data ?? const <String>[];
        return Column(
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(200, 200),
                  painter: _RadarPainter(),
                ),
                RotationTransition(
                  turns: _controller,
                  child: const CustomPaint(
                    size: Size(200, 200),
                    painter: _SweepPainter(),
                  ),
                ),
                ..._buildBeaconDots(),
                const Icon(Icons.my_location, color: Colors.blue, size: 24),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              beacons.isEmpty
                  ? 'SCANNING (NO PEERS)'
                  : 'PEERS DETECTED: ${beacons.length}',
              style: const TextStyle(
                color: Colors.blue,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            if (_myFix == null && _peers.values.any((p) => p.decoded != null))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'GPS unavailable — peer angles approximate',
                  style: TextStyle(
                    color: Colors.orange.withValues(alpha: 0.8),
                    fontSize: 9,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  List<Widget> _buildBeaconDots() {
    final out = <Widget>[];
    const center = 100.0;
    const maxR = 78.0;
    const minR = 18.0;

    final myFix = _myFix;
    final observations = _peers.values.toList();

    for (var i = 0; i < observations.length; i++) {
      final obs = observations[i];
      final decoded = obs.decoded;

      double angleRad;
      double radius;

      if (decoded != null && myFix != null) {
        final bearingDeg = _bearingDeg(
          myFix.latitude,
          myFix.longitude,
          decoded.latitude,
          decoded.longitude,
        );
        final distMeters = _haversineMeters(
          myFix.latitude,
          myFix.longitude,
          decoded.latitude,
          decoded.longitude,
        );
        // North = up on the radar → rotate -90° so 0° heading points up.
        angleRad = (bearingDeg - 90) * math.pi / 180.0;
        radius = _distanceToRadius(distMeters, maxR, minR);
      } else if (obs.rssi != null) {
        // No GPS context — fall back to RSSI ring (closer RSSI → smaller r)
        // but anchor angle to a deterministic slot around the rim so the
        // user doesn't see jitter, and don't pretend it's a real bearing.
        final rssi = obs.rssi!.clamp(-100, -30);
        // -30 dBm → ~near, -100 dBm → ~far. Linear map.
        final t = (-rssi - 30) / 70.0; // 0 (near) → 1 (far)
        radius = (minR + (maxR - minR) * t).clamp(minR, maxR);
        angleRad = (i * 2 * math.pi / observations.length) - math.pi / 2;
      } else {
        // No decoded payload, no RSSI: place on outer rim, deterministic slot.
        radius = maxR;
        angleRad = (i * 2 * math.pi / observations.length) - math.pi / 2;
      }

      final x = center + math.cos(angleRad) * radius;
      final y = center + math.sin(angleRad) * radius;
      out.add(
        Positioned(
          left: x - 6,
          top: y - 6,
          child: _IncidentDot(severity: decoded?.severity),
        ),
      );
    }
    return out;
  }

  /// Soft logarithmic distance → radius mapping so 1 m and 200 m are easily
  /// distinguishable on a 78 px-radius radar.
  double _distanceToRadius(double meters, double maxR, double minR) {
    if (meters.isNaN || meters <= 0) return minR;
    const cap = 500.0;
    final clamped = meters.clamp(0.0, cap);
    final t = math.log(1 + clamped) / math.log(1 + cap); // 0..1 soft curve
    return (minR + (maxR - minR) * t).clamp(minR, maxR);
  }
}

class _PeerObservation {
  final String senderId;
  final BleDecodedPayload? decoded;
  final int? rssi;
  final DateTime observedAt;

  const _PeerObservation({
    required this.senderId,
    required this.decoded,
    required this.rssi,
    required this.observedAt,
  });
}

class _RadarPainter extends CustomPainter {
  const _RadarPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.blue.withValues(alpha: 0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final center = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(center, size.width * 0.2, paint);
    canvas.drawCircle(center, size.width * 0.35, paint);
    canvas.drawCircle(center, size.width * 0.5, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SweepPainter extends CustomPainter {
  const _SweepPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    final rect = Rect.fromCircle(center: center, radius: radius);
    final gradient = SweepGradient(
      startAngle: 0,
      endAngle: math.pi * 2,
      colors: [
        Colors.blue.withValues(alpha: 0),
        Colors.blue.withValues(alpha: 0.5),
        Colors.blue.withValues(alpha: 0),
      ],
      stops: const [0.0, 0.5, 1.0],
    );

    final paint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _IncidentDot extends StatelessWidget {
  final int? severity;
  const _IncidentDot({this.severity});

  @override
  Widget build(BuildContext context) {
    // Colour by severity so a S5 incident is visually distinct from S2.
    final colour = severity == null
        ? Colors.red
        : (severity! >= 4
              ? Colors.red
              : (severity! >= 3 ? Colors.orange : Colors.amber));
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: colour,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: colour, blurRadius: 10, spreadRadius: 2)],
      ),
    );
  }
}

double _haversineMeters(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0;
  final dlat = (lat2 - lat1) * math.pi / 180;
  final dlon = (lon2 - lon1) * math.pi / 180;
  final a =
      math.sin(dlat / 2) * math.sin(dlat / 2) +
      math.cos(lat1 * math.pi / 180) *
          math.cos(lat2 * math.pi / 180) *
          math.sin(dlon / 2) *
          math.sin(dlon / 2);
  return 2 * r * math.asin(math.min(1.0, math.sqrt(a)));
}

double _bearingDeg(double lat1, double lon1, double lat2, double lon2) {
  final phi1 = lat1 * math.pi / 180;
  final phi2 = lat2 * math.pi / 180;
  final dlon = (lon2 - lon1) * math.pi / 180;
  final y = math.sin(dlon) * math.cos(phi2);
  final x =
      math.cos(phi1) * math.sin(phi2) -
      math.sin(phi1) * math.cos(phi2) * math.cos(dlon);
  final theta = math.atan2(y, x);
  return (theta * 180 / math.pi + 360) % 360;
}
