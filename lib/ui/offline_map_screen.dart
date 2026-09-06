import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../config/map_tile_config.dart';
import '../logging/app_log.dart';
import '../services/location_service.dart';
import '../services/map_tile_cache.dart';

class OfflineMapScreen extends ConsumerStatefulWidget {
  const OfflineMapScreen({super.key});

  @override
  ConsumerState<OfflineMapScreen> createState() => _OfflineMapScreenState();
}

class _OfflineMapScreenState extends ConsumerState<OfflineMapScreen> {
  StreamSubscription<DownloadProgress>? _progressSub;
  StreamSubscription<TileEvent>? _tileEventSub;

  DownloadProgress? _progress;
  bool _busy = false;
  String? _lastStatus;

  double _radiusKm = 25.0;
  double _minZoom = 11.0;
  double _maxZoom = 16.0;

  @override
  void dispose() {
    unawaited(_progressSub?.cancel());
    unawaited(_tileEventSub?.cancel());
    super.dispose();
  }

  Future<void> _startDownloadAroundMe() async {
    if (_busy) return;
    if (kIsWeb) {
      setState(
        () => _lastStatus = 'Offline map downloads are not supported on web.',
      );
      return;
    }
    if (!fmtcMapCacheReady) {
      setState(
        () => _lastStatus =
            'Offline cache backend not ready on this device. Maps will use network tiles only.',
      );
      return;
    }

    setState(() {
      _busy = true;
      _progress = null;
      _lastStatus = 'Resolving current location…';
    });

    try {
      final fix = await ref.read(locationServiceProvider).getCurrentLocation();
      if (!mounted) return;

      if (fix.source == 'unknown') {
        setState(() {
          _busy = false;
          _lastStatus =
              'Could not get a usable location. Enable location services to download an offline region.';
        });
        return;
      }

      final center = LatLng(fix.latitude, fix.longitude);

      final radiusKm = _radiusKm;
      final minZoom = _minZoom;
      final maxZoom = _maxZoom;

      final region = CircleRegion(center, radiusKm).toDownloadable(
        minZoom: minZoom.round(),
        maxZoom: maxZoom.round(),
        options: TileLayer(
          urlTemplate: MapTileConfig.effectiveUrlTemplate,
          subdomains: MapTileConfig.effectiveSubdomains,
          userAgentPackageName: 'com.roadsos.app',
        ),
      );

      final tiles = await FMTCStore(
        kFmtcRoadsosOsmStore,
      ).download.countTiles(region);
      if (!mounted) return;

      setState(() {
        _lastStatus =
            'Downloading ~${tiles.toString()} tiles (r=${radiusKm.toStringAsFixed(0)}km, z${minZoom.toStringAsFixed(0)}–${maxZoom.toStringAsFixed(0)})…';
      });

      final (:downloadProgress, :tileEvents) = FMTCStore(kFmtcRoadsosOsmStore)
          .download
          .startForeground(
            region: region,
            parallelThreads: 6,
            skipExistingTiles: true,
            skipSeaTiles: true,
          );

      await _progressSub?.cancel();
      await _tileEventSub?.cancel();

      _progressSub = downloadProgress.listen(
        (p) {
          if (!mounted) return;
          final complete =
              p.attemptedTilesCount >= p.maxTilesCount &&
              p.remainingTilesCount == 0;
          setState(() {
            _progress = p;
            _busy = !complete;
            _lastStatus = complete
                ? 'Offline region download complete.'
                : 'Downloading… ${p.successfulTilesCount}/${p.maxTilesCount} tiles';
          });
        },
        onError: (e, st) {
          appLog.w(
            'FMTC download progress stream error',
            error: e,
            stackTrace: st,
          );
        },
      );

      _tileEventSub = tileEvents.listen(
        (_) {},
        onError: (e, st) {
          appLog.w('FMTC tile events stream error', error: e, stackTrace: st);
        },
      );

      // No await on completion: download runs in foreground thread; UI updates via stream.
    } on Object catch (e, st) {
      appLog.w('Offline map download failed', error: e, stackTrace: st);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _lastStatus = 'Offline download failed: ${e.runtimeType}.';
      });
      return;
    }
  }

  Future<void> _cancelDownload() async {
    try {
      await FMTCStore(kFmtcRoadsosOsmStore).download.cancel();
    } on Object catch (e, st) {
      appLog.w('FMTC download cancel failed', error: e, stackTrace: st);
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _lastStatus = 'Download cancelled.';
      _progress = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text(
          'OFFLINE MAPS',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
        ),
        backgroundColor: Colors.transparent,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'OFFLINE TILE CACHE',
              style: TextStyle(
                color: Colors.white38,
                fontWeight: FontWeight.w900,
                fontSize: 10,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            _cacheStatusCard(),
            const SizedBox(height: 18),
            _controlsCard(),
            const Spacer(),
            if (_busy && _progress != null) ...[
              LinearProgressIndicator(
                value: _progress!.maxTilesCount <= 0
                    ? null
                    : (_progress!.successfulTilesCount /
                          _progress!.maxTilesCount),
                backgroundColor: Colors.white10,
                color: scheme.primary,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _lastStatus ?? 'Downloading…',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _cancelDownload,
                    child: const Text('CANCEL'),
                  ),
                ],
              ),
            ] else ...[
              if (_lastStatus != null) ...[
                Text(
                  _lastStatus!,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: _busy ? null : _startDownloadAroundMe,
                  icon: const Icon(Icons.download),
                  label: Text(
                    'DOWNLOAD AROUND ME (${_radiusKm.toStringAsFixed(0)}KM)',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'This downloads map tiles for offline use. Size depends on zoom levels and your area.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.38),
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _controlsCard() {
    if (kIsWeb) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'DOWNLOAD SETTINGS',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontWeight: FontWeight.w900,
              fontSize: 10,
              letterSpacing: 1.3,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Radius: ${_radiusKm.toStringAsFixed(0)} km',
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w700,
            ),
          ),
          Slider(
            value: _radiusKm,
            min: 5,
            max: 80,
            divisions: 15,
            label: '${_radiusKm.toStringAsFixed(0)} km',
            onChanged: _busy ? null : (v) => setState(() => _radiusKm = v),
          ),
          const SizedBox(height: 8),
          Text(
            'Zoom: ${_minZoom.toStringAsFixed(0)}–${_maxZoom.toStringAsFixed(0)}',
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w700,
            ),
          ),
          RangeSlider(
            values: RangeValues(_minZoom, _maxZoom),
            min: 8,
            max: 18,
            divisions: 10,
            labels: RangeLabels(
              _minZoom.toStringAsFixed(0),
              _maxZoom.toStringAsFixed(0),
            ),
            onChanged: _busy
                ? null
                : (r) => setState(() {
                    final start = r.start.roundToDouble();
                    final end = r.end.roundToDouble();
                    _minZoom = start <= end ? start : end;
                    _maxZoom = end >= start ? end : start;
                  }),
          ),
          Text(
            'Tip: higher zoom = more tiles (bigger download).',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.35),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _cacheStatusCard() {
    if (kIsWeb) {
      return _infoCard(
        icon: Icons.public,
        title: 'Web limitation',
        body:
            'Offline tile downloads are not supported on web. Install RoadSOS on a phone for offline caching.',
      );
    }

    if (!fmtcMapCacheReady) {
      return _infoCard(
        icon: Icons.warning_amber_rounded,
        title: 'Offline cache unavailable',
        body:
            'Tile cache backend did not initialize on this device. Maps will still work online.',
      );
    }

    return FutureBuilder<({double size, int length, int hits, int misses})>(
      future: FMTCStore(kFmtcRoadsosOsmStore).stats.all,
      builder: (context, snapshot) {
        final stats = snapshot.data;
        final tileCount = stats?.length.toString() ?? '…';
        final sizeKiB = stats?.size;
        final sizeLabel = sizeKiB == null ? '…' : _formatKiB(sizeKiB);
        return _infoCard(
          icon: Icons.map,
          title: 'Cache store: $kFmtcRoadsosOsmStore',
          body: 'Tiles cached: $tileCount\nApprox size: $sizeLabel',
        );
      },
    );
  }

  String _formatKiB(double kib) {
    final mib = kib / 1024.0;
    if (mib < 1024.0) return '${mib.toStringAsFixed(1)} MiB';
    final gib = mib / 1024.0;
    return '${gib.toStringAsFixed(2)} GiB';
  }

  Widget _infoCard({
    required IconData icon,
    required String title,
    required String body,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.blue.withValues(alpha: 0.85)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  body,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
