import 'package:flutter/foundation.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';

import '../logging/app_log.dart';

/// ObjectBox-backed OSM tile store for [flutter_map] (`flutter_map_tile_caching`).
const String kFmtcRoadsosOsmStore = 'roadsos_osm';

bool fmtcMapCacheReady = false;

/// Initialise FMTC before [runApp]. Safe to skip on web (unsupported).
Future<void> initializeFmtcMapCache() async {
  if (kIsWeb) return;
  try {
    await FMTCObjectBoxBackend().initialise();
    await FMTCStore(kFmtcRoadsosOsmStore).manage.create();
    fmtcMapCacheReady = true;
  } on Object catch (e, st) {
    fmtcMapCacheReady = false;
    appLog.w(
      'FMTC map cache init failed — using network tiles only',
      error: e,
      stackTrace: st,
    );
  }
}
