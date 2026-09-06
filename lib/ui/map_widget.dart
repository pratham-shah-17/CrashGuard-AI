import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map_animations/flutter_map_animations.dart';
import '../config/map_tile_config.dart';
import '../logging/app_log.dart';
import '../services/emergency_orchestrator.dart';
import '../models/facility.dart';

/// A robust, offline-capable Map widget for RoadSOS.
///
/// Features:
/// - Raster tiles from [MapTileConfig] (defaults to Carto CDN — not OSM.org;
///   supports Mappls/CARTO/self-hosted URLs via env)
/// - Displays user location, reported incidents, and nearby facilities
/// - Supports auto-centering on user location
class RoadSosMap extends StatefulWidget {
  final SOSState state;
  final bool autoCenter;

  const RoadSosMap({super.key, required this.state, this.autoCenter = true});

  @override
  State<RoadSosMap> createState() => _RoadSosMapState();
}

class _RoadSosMapState extends State<RoadSosMap> with TickerProviderStateMixin {
  late final AnimatedMapController _mapController;
  // NOTE (SOS reliability): keep the SOS map on network tiles only.
  // Offline caching is handled by `OfflineMapScreen` + FMTC. In the SOS
  // surface, using the cache provider can hide network/tile failures behind
  // silent cache logic and has produced “blank grey map” reports.
  late final TileProvider _tileProvider = NetworkTileProvider();
  int _tileErrorCount = 0;
  int _tileLayerNonce = 0;
  DateTime _mountedAt = DateTime.now();

  bool get _templateLooksValid {
    final t = MapTileConfig.effectiveUrlTemplate;
    return t.contains('{z}') && t.contains('{x}') && t.contains('{y}');
  }

  String? get _fallbackUrl {
    final t = MapTileConfig.effectiveUrlTemplate;
    // Fallback chain for reliability (demo safety):
    // - If custom provider fails (keys/restrictions), fall back to Carto.
    // - If Carto fails (blocked network / DNS / captive portal), fall back to
    //   OSM tile CDN for demo resilience (do not ship high-volume traffic there).
    if (!t.contains('basemaps.cartocdn.com')) {
      return MapTileConfig.cartoDarkMatter;
    }
    return MapTileConfig.tileOpenstreetmapOrgViolatesPolicyAtScale;
  }

  // Cache tile provider intentionally not used in SOS map.

  @override
  void initState() {
    super.initState();
    _mapController = AnimatedMapController(vsync: this);
    _mountedAt = DateTime.now();
  }

  @override
  void didUpdateWidget(RoadSosMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.autoCenter && widget.state.location != null) {
      final loc = widget.state.location!;
      _mapController.animateTo(
        dest: LatLng(loc.latitude, loc.longitude),
        zoom: 15,
      );
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasFix =
        widget.state.location != null &&
        widget.state.location!.source != 'unknown' &&
        !(widget.state.location!.latitude == 0.0 &&
            widget.state.location!.longitude == 0.0);
    final userLoc = hasFix
        ? LatLng(
            widget.state.location!.latitude,
            widget.state.location!.longitude,
          )
        : null;

    return Container(
      height: 300,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Container(color: Colors.black),
          FlutterMap(
            mapController: _mapController.mapController,
            options: MapOptions(
              initialCenter: userLoc ?? const LatLng(20.5937, 78.9629),
              initialZoom: userLoc != null ? 15 : 4.5,
              minZoom: 2.5,
              maxZoom: 18,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              TileLayer(
                key: ValueKey(
                  'tiles_${_tileLayerNonce}_${MapTileConfig.effectiveUrlTemplate}',
                ),
                urlTemplate: MapTileConfig.effectiveUrlTemplate,
                subdomains: MapTileConfig.effectiveSubdomains,
                userAgentPackageName: 'com.roadsos.app',
                tileProvider: _tileProvider,
                fallbackUrl: _fallbackUrl,
                errorTileCallback: (tile, error, stackTrace) {
                  // Avoid log spam; still record enough to debug.
                  _tileErrorCount += 1;
                  if (_tileErrorCount <= 3 || _tileErrorCount % 20 == 0) {
                    appLog.w(
                      '[Map] Tile load error (#$_tileErrorCount) z=${tile.coordinates.z} x=${tile.coordinates.x} y=${tile.coordinates.y}',
                      error: error,
                      stackTrace: stackTrace,
                    );
                  }
                  if (mounted && _tileErrorCount == 1) setState(() {});
                },
              ),
              MarkerLayer(
                markers: [
                  // User Location Marker
                  if (userLoc != null)
                    Marker(
                      point: userLoc,
                      width: 40,
                      height: 40,
                      child: _buildUserMarker(),
                    ),

                  // Incident Markers
                  ..._buildIncidentMarkers(),

                  // Facility Markers (seeded + cloud-synced via PowerSync when configured)
                  ..._buildFacilityMarkers(),
                ],
              ),
            ],
          ),
          Positioned(
            left: 8,
            bottom: 8,
            right: 56,
            child: IgnorePointer(
              child: Text(
                MapTileConfig.attributionLabel,
                style: TextStyle(
                  fontSize: 9,
                  color: Colors.white.withValues(alpha: 0.45),
                  shadows: const [Shadow(color: Colors.black54, blurRadius: 4)],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),

          // Map Overlay Controls
          Positioned(
            right: 12,
            bottom: 12,
            child: Column(
              children: [
                _MapButton(
                  icon: Icons.my_location,
                  onTap: () {
                    if (widget.state.location != null) {
                      _mapController.animateTo(dest: userLoc, zoom: 15);
                    }
                  },
                ),
                const SizedBox(height: 8),
                _MapButton(
                  icon: Icons.add,
                  onTap: () => _mapController.animatedZoomIn(),
                ),
                const SizedBox(height: 8),
                _MapButton(
                  icon: Icons.remove,
                  onTap: () => _mapController.animatedZoomOut(),
                ),
              ],
            ),
          ),

          // Fail-safe overlay: never allow a silent grey map.
          if (!_templateLooksValid || _tileErrorCount > 0)
            Positioned(
              left: 12,
              top: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.78),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: _templateLooksValid
                          ? Colors.amber
                          : Colors.redAccent,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        !_templateLooksValid
                            ? 'Map tiles misconfigured (missing {z}/{x}/{y}).'
                            : 'Map tiles failed to load. Check internet / tile provider.\n'
                                  'Template: ${MapTileConfig.effectiveUrlTemplate}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          height: 1.25,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _tileErrorCount = 0;
                          _tileLayerNonce += 1; // forces TileLayer rebuild
                        });
                      },
                      child: const Text('RETRY'),
                    ),
                  ],
                ),
              ),
            ),

          // If no tile errors are reported but the map still appears blank,
          // show a timed hint so users aren't left with a silent grey box.
          if (_templateLooksValid && _tileErrorCount == 0)
            Positioned(
              left: 12,
              bottom: 46,
              child: Builder(
                builder: (context) {
                  final seconds = DateTime.now()
                      .difference(_mountedAt)
                      .inSeconds;
                  if (seconds < 6) return const SizedBox.shrink();
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: const Text(
                      'Map still loading… If this stays blank, check internet or switch networks.',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildUserMarker() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.2),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.blue, width: 2),
      ),
      child: const Center(
        child: Icon(Icons.navigation, size: 20, color: Colors.blue),
      ),
    );
  }

  List<Marker> _buildIncidentMarkers() {
    if (widget.state.incidentId == null || widget.state.location == null) {
      return [];
    }
    if (widget.state.location!.source == 'unknown') return [];

    return [
      Marker(
        point: LatLng(
          widget.state.location!.latitude,
          widget.state.location!.longitude,
        ),
        width: 50,
        height: 50,
        child: const Icon(Icons.emergency, color: Colors.red, size: 40),
      ),
    ];
  }

  List<Marker> _buildFacilityMarkers() {
    return widget.state.nearbyFacilities.map((facility) {
      return Marker(
        point: facility.location,
        width: 30,
        height: 30,
        child: _FacilityMarker(facility: facility),
      );
    }).toList();
  }
}

class _FacilityMarker extends StatelessWidget {
  final Facility facility;

  const _FacilityMarker({required this.facility});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color color;

    switch (facility.type.toLowerCase()) {
      case 'hospital':
      case 'ambulance':
      case 'primary_health_centre':
        icon = Icons.local_hospital;
        color = Colors.green;
        break;
      case 'fire_station':
        icon = Icons.fire_truck;
        color = Colors.orange;
        break;
      case 'police':
        icon = Icons.local_police;
        color = Colors.blue;
        break;
      case 'towing':
      case 'rescue':
        icon = Icons.car_repair;
        color = Colors.amber;
        break;
      case 'puncture_shop':
      case 'mechanic':
        icon = Icons.build;
        color = Colors.brown;
        break;
      case 'showroom':
        icon = Icons.store;
        color = Colors.purple;
        break;
      default:
        icon = Icons.place;
        color = Colors.grey;
    }

    return GestureDetector(
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${facility.name} (${facility.type})'
              '${facility.dataSource != null ? ' · ${facility.dataSource}' : ''}',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.8),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 1),
        ),
        child: Icon(icon, size: 16, color: Colors.white),
      ),
    );
  }
}

class _MapButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _MapButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white10),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}
