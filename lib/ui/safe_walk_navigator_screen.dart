import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../services/app_locale_controller.dart';
import '../services/emergency_orchestrator.dart'
    show voiceAssistantServiceProvider;
import '../services/proactive_monitor_service.dart';
import '../services/safe_walk_navigator_service.dart';

/// Full-screen Safe Walk Navigator: live OSM map + AirTag-style direction
/// arrow + walking-pace ETA + OSRM turn-by-turn cards + flutter_tts voice
/// callouts + 30m geofence auto-arrival.
///
/// Replaces the old 320-pixel popup that just opened Google Maps.
class SafeWalkNavigatorScreen extends ConsumerStatefulWidget {
  const SafeWalkNavigatorScreen({
    super.key,
    required this.destination,
    required this.destinationName,
    this.deadManDuration = const Duration(minutes: 30),
  });

  final LatLng destination;
  final String destinationName;
  final Duration deadManDuration;

  @override
  ConsumerState<SafeWalkNavigatorScreen> createState() =>
      _SafeWalkNavigatorScreenState();
}

class _SafeWalkNavigatorScreenState
    extends ConsumerState<SafeWalkNavigatorScreen> {
  final MapController _mapController = MapController();
  StreamSubscription<CompassEvent>? _compassSub;
  String? _lastSpoken;
  Timer? _voiceCueTimer;
  bool _autoEndedOnArrival = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Start the dead-man + Family Circle publish (existing behaviour).
      ref
          .read(proactiveMonitorProvider.notifier)
          .startSafeWalk(widget.destinationName, widget.deadManDuration);
      // Start route + GPS stream + bearing math.
      await ref
          .read(safeWalkNavigatorProvider.notifier)
          .start(
            destination: widget.destination,
            destinationName: widget.destinationName,
          );
      _compassSub = FlutterCompass.events?.listen((e) {
        if (e.heading != null) {
          ref
              .read(safeWalkNavigatorProvider.notifier)
              .updateDeviceHeading(e.heading!);
        }
      });
      // Welcome cue.
      final locale = ref.read(appLocaleProvider).languageCode;
      await _speak(switch (locale) {
        'hi' =>
          'सुरक्षित चलना शुरू। मैं आपको ${widget.destinationName} तक मार्गदर्शन करूँगा।',
        'ta' =>
          'பாதுகாப்பான நடைபயணம் தொடங்கியது. ${widget.destinationName}க்கு உங்களை அழைத்துச் செல்கிறேன்.',
        'te' =>
          'సురక్షిత నడక ప్రారంభం. ${widget.destinationName}కు మిమ్మల్ని తీసుకువెళతాను.',
        _ =>
          'Safe Walk navigation started. Guiding you to ${widget.destinationName}.',
      });
    });
  }

  @override
  void dispose() {
    _compassSub?.cancel();
    _voiceCueTimer?.cancel();
    // Stop the navigator (clears state); leave the dead-man monitor running
    // so the user can keep walking even after closing the screen.
    ref.read(safeWalkNavigatorProvider.notifier).stop();
    super.dispose();
  }

  Future<void> _speak(String text) async {
    try {
      await ref.read(voiceAssistantServiceProvider).speak(text);
    } on Object catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final nav = ref.watch(safeWalkNavigatorProvider);

    // Voice cue when we cross into a new turn step.
    final speak = nav.lastSpokenInstruction;
    if (speak != null && speak != _lastSpoken) {
      _lastSpoken = speak;
      _voiceCueTimer?.cancel();
      _voiceCueTimer = Timer(const Duration(milliseconds: 200), () {
        _speak(speak);
      });
    }

    // Auto-end on arrival.
    if (nav.arrived && !_autoEndedOnArrival) {
      _autoEndedOnArrival = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _onArrival();
      });
    }

    final mePoint = nav.lastFix;
    if (mePoint != null) {
      // Re-center the map gently on the user.
      try {
        _mapController.move(mePoint, _mapController.camera.zoom);
      } on Object catch (_) {}
    }

    return Scaffold(
      backgroundColor: const Color(0xFF080A0D),
      body: SafeArea(
        child: Stack(
          children: [
            _liveMap(nav),
            _topHud(nav),
            Positioned(left: 0, right: 0, bottom: 0, child: _bottomPanel(nav)),
          ],
        ),
      ),
    );
  }

  // ── Map ─────────────────────────────────────────────────────────────────

  Widget _liveMap(SafeWalkNavState nav) {
    final markers = <Marker>[];
    if (nav.lastFix != null) {
      markers.add(
        Marker(
          point: nav.lastFix!,
          width: 56,
          height: 56,
          child: const _MeDot(),
        ),
      );
    }
    if (nav.destination != null) {
      markers.add(
        Marker(
          point: nav.destination!,
          width: 44,
          height: 44,
          child: const Icon(Icons.flag, color: Color(0xFFE8281A), size: 36),
        ),
      );
    }
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter:
            nav.lastFix ?? nav.destination ?? const LatLng(12.97, 77.59),
        initialZoom: 17,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'app.roadsos',
          maxZoom: 19,
        ),
        if (nav.route.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: nav.route,
                strokeWidth: 6,
                color: const Color(0xFF00B8A0),
              ),
            ],
          ),
        if (markers.isNotEmpty) MarkerLayer(markers: markers),
      ],
    );
  }

  // ── Top HUD ─────────────────────────────────────────────────────────────

  Widget _topHud(SafeWalkNavState nav) {
    return Positioned(
      top: 12,
      left: 12,
      right: 12,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF1F2933)),
          ),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SAFE WALK · TO ${widget.destinationName.toUpperCase()}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      nav.routingDegraded
                          ? 'Route offline · straight-line guidance'
                          : nav.steps.isEmpty
                          ? 'Acquiring route…'
                          : _currentInstruction(nav),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: nav.routingDegraded
                            ? const Color(0xFFFFB400)
                            : Colors.white70,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (nav.steps.isNotEmpty && !nav.routingDegraded)
                IconButton(
                  tooltip: 'Repeat instruction',
                  icon: const Icon(Icons.campaign, color: Color(0xFF00B8A0)),
                  onPressed: () async {
                    await HapticFeedback.selectionClick();
                    await _speak(_currentInstruction(nav));
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _currentInstruction(SafeWalkNavState nav) {
    if (nav.steps.isEmpty) return '';
    final step = nav.steps[nav.currentStepIndex];
    final m = nav.distanceToNextStepMeters.round();
    if (m <= 15) return step.instruction;
    return 'In $m m: ${step.instruction}';
  }

  // ── Bottom panel: arrow + distance + ETA + buttons ─────────────────────

  Widget _bottomPanel(SafeWalkNavState nav) {
    final relativeBearing = _wrap360(
      nav.bearingToDestinationDeg - nav.deviceHeadingDeg,
    );
    final etaMin = (nav.estimatedSecondsRemaining / 60).ceil();
    final distM = nav.distanceToDestinationMeters;
    final distLabel = distM >= 1000
        ? '${(distM / 1000).toStringAsFixed(distM >= 10000 ? 0 : 1)} km'
        : '${distM.round()} m';

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
      decoration: const BoxDecoration(
        color: Color(0xFF080A0D),
        border: Border(top: BorderSide(color: Color(0xFF1F2933))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _ArrowBadge(angleDeg: relativeBearing),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      distLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'ETA ${etaMin == 0 ? '<1' : etaMin} min · walking pace',
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
              ),
              if (nav.arrived)
                const Icon(
                  Icons.flag_circle,
                  color: Color(0xFF00B8A0),
                  size: 36,
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFF1F2933)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () async {
                    await HapticFeedback.selectionClick();
                    await _speak(
                      'You are $distLabel, ${etaMin == 0 ? 'less than a minute' : '$etaMin minutes'} from ${widget.destinationName}.',
                    );
                  },
                  icon: const Icon(Icons.record_voice_over),
                  label: const Text('SPEAK ETA'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE8281A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _endWalk,
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('END SAFE WALK'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _endWalk() {
    ref.read(proactiveMonitorProvider.notifier).endSafeWalk();
    if (mounted) Navigator.of(context).maybePop();
  }

  Future<void> _onArrival() async {
    await HapticFeedback.heavyImpact();
    await _speak(
      'You have arrived at ${widget.destinationName}. Ending Safe Walk.',
    );
    if (!mounted) return;
    ref.read(proactiveMonitorProvider.notifier).endSafeWalk();
    // Surface the arrival before popping so the user sees confirmation.
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Arrived'),
        content: Text(
          'You reached ${widget.destinationName}. RoadSOS auto-ended the Safe Walk so no SOS will trigger.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }
}

double _wrap360(double d) => ((d % 360) + 360) % 360;

// ── Reusable bits ──────────────────────────────────────────────────────────

class _ArrowBadge extends StatelessWidget {
  const _ArrowBadge({required this.angleDeg});

  final double angleDeg;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        color: const Color(0xFF00B8A0).withValues(alpha: 0.16),
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFF00B8A0), width: 2),
      ),
      child: Center(
        child: Transform.rotate(
          angle: angleDeg * math.pi / 180,
          child: const Icon(
            Icons.navigation,
            color: Color(0xFF00B8A0),
            size: 56,
          ),
        ),
      ),
    );
  }
}

class _MeDot extends StatelessWidget {
  const _MeDot();

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: const Color(0xFF4a90d9).withValues(alpha: 0.22),
            shape: BoxShape.circle,
          ),
        ),
        Container(
          width: 14,
          height: 14,
          decoration: const BoxDecoration(
            color: Color(0xFF4a90d9),
            shape: BoxShape.circle,
          ),
        ),
      ],
    );
  }
}
