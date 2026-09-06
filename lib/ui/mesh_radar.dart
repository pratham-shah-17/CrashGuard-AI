import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/mesh_network_service.dart';

class MeshRadar extends ConsumerStatefulWidget {
  const MeshRadar({super.key});

  @override
  ConsumerState<MeshRadar> createState() => _MeshRadarState();
}

class _MeshRadarState extends ConsumerState<MeshRadar>
    with SingleTickerProviderStateMixin {
  late AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    // Start scanning
    ref.read(meshNetworkServiceProvider).listenForSosBeacons();
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final beacons = ref.watch(meshNetworkServiceProvider).discoveredBeacons;

    return StreamBuilder<List<String>>(
      stream: beacons,
      initialData: const [],
      builder: (context, snapshot) {
        final nodes = snapshot.data ?? [];

        return Container(
          height: 200,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white10),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Radar circles
              ...List.generate(5, (i) => _buildCircle(i)),

              // Orbiting dot with pulsing glow
              // ⚡ Bolt Optimization: Use CustomPainter for both the sweeping radar beam
              // and the pulsing dot, passing the _rotationController to the repaint parameter.
              // This completely bypasses the widget tree and delegates positioning, pulsing,
              // and glow logic to the canvas layer, saving thousands of widget rebuilds.
              CustomPaint(
                painter: _SweepingDotPainter(_rotationController, 75.0),
                size: const Size(180, 180),
              ),

              // Discovered Nodes
              ...nodes.asMap().entries.map((entry) {
                final idx = entry.key;
                final angle =
                    (idx * 137.5) * pi / 180; // Golden angle for distribution
                final dist = 40.0 + (idx * 15);
                return _buildNode(angle, dist);
              }),

              // Center text
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'MESH RADAR',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                      color: Colors.blue.withValues(alpha: 0.6),
                    ),
                  ),
                  Text(
                    '${nodes.length} NEARBY',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Foreground only',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withValues(alpha: 0.35),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCircle(int index) {
    final radius = (index + 1) * 30.0;
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
    );
  }

  Widget _buildNode(double angle, double dist) {
    return Transform.translate(
      offset: Offset(cos(angle) * dist, sin(angle) * dist),
      child: Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: Colors.red,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Colors.red, blurRadius: 8)],
        ),
      ),
    );
  }
}

class _SweepingDotPainter extends CustomPainter {
  final Animation<double> animation;
  final double orbitRadius;

  const _SweepingDotPainter(this.animation, this.orbitRadius)
    : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final currentAngle = animation.value * 2 * pi;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(currentAngle);

    // 1. Draw the static beam pointing at angle 0 (because we rotated the canvas)
    final dotX = orbitRadius;
    const dotY = 0.0;

    final beamPaint = Paint()
      ..color = const Color(0xFF00FFFF).withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;

    const beamWidth = 0.3; // Width of the beam in radians
    final path = Path();
    path.moveTo(0, 0);

    final angle1 = -beamWidth / 2;
    path.lineTo(cos(angle1) * orbitRadius, sin(angle1) * orbitRadius);
    path.lineTo(dotX, dotY);

    final angle2 = beamWidth / 2;
    path.lineTo(cos(angle2) * orbitRadius, sin(angle2) * orbitRadius);
    path.close();

    canvas.drawPath(path, beamPaint);

    final glowPaint = Paint()
      ..color = const Color(0xFF00FFFF).withValues(alpha: 0.15)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawPath(path, glowPaint);

    // 2. Draw the pulsing dot at (dotX, dotY)
    final pulseValue = (sin(currentAngle * 3) + 1) / 2;

    // Outer glow
    final outerGlowPaint = Paint()
      ..color = const Color(
        0xFF00FFFF,
      ).withValues(alpha: 0.2 + (pulseValue * 0.3))
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 10 + (pulseValue * 20));
    canvas.drawCircle(Offset(dotX, dotY), 5 + (pulseValue * 4), outerGlowPaint);

    // Inner glow
    final innerGlowPaint = Paint()
      ..color = const Color(0xFF00FFFF)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 5 + (pulseValue * 15));
    canvas.drawCircle(Offset(dotX, dotY), 5 + (pulseValue * 3), innerGlowPaint);

    // Core dot
    final dotPaint = Paint()
      ..color = const Color(
        0xFF00FFFF,
      ).withValues(alpha: 0.3 + (pulseValue * 0.7))
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(dotX, dotY), 5, dotPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SweepingDotPainter oldDelegate) => true;
}
