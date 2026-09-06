import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Raster basemap URLs for [flutter_map](https://pub.dev/packages/flutter_map).
///
/// **Do not** ship production traffic to `tile.openstreetmap.org` — OSM's
/// [Tile Usage Policy](https://operations.osmfoundation.org/policies/tiles/)
/// forbids automated / high-volume use from commercial apps.
///
/// Defaults use **Carto Basemaps** CDN (common choice for startups; show
/// attribution). For India-specific road authority data and INR pricing,
/// configure [Mappls / Maps.co](https://about.mappls.com/) (formerly MapmyIndia)
/// via [effectiveUrlTemplate]. Self-hosted options: Protomaps, OpenMapTiles.
class MapTileConfig {
  MapTileConfig._();

  /// Forbidden for scaled / commercial apps — OSM-operated CDN only for
  /// low-volume development if you comply with their policy.
  static const String tileOpenstreetmapOrgViolatesPolicyAtScale =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  /// Carto "Dark Matter" — matches typical dark emergency UIs.
  static const String cartoDarkMatter =
      'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png';

  /// Carto "Positron" — light basemap.
  static const String cartoPositron =
      'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png';

  /// Subdomains Carto serves tiles from (rotate load).
  static const List<String> cartoSubdomains = ['a', 'b', 'c', 'd'];

  /// Set `MAP_TILE_URL_TEMPLATE` in `assets/.env` to override fully, e.g.:
  /// - Mappls raster (pattern from Maps.co dashboard after signup)
  /// - Self-hosted OpenMapTiles: `https://tiles.example.com/{z}/{x}/{y}.png`
  /// - Protomaps PMtiles-backed HTTP endpoints you operate
  ///
  /// Template must include `{z}`, `{x}`, `{y}`. Use `{s}` only if your CDN
  /// uses subdomains and you set [effectiveSubdomains] accordingly.
  static String get effectiveUrlTemplate {
    final custom = dotenv.maybeGet('MAP_TILE_URL_TEMPLATE')?.trim();
    if (custom != null && custom.isNotEmpty) return custom;

    final preset =
        dotenv.maybeGet('MAP_TILE_PRESET')?.trim().toLowerCase() ?? '';

    switch (preset) {
      case 'carto_light':
      case 'positron':
        return cartoPositron;
      case 'carto_dark':
      case 'dark_matter':
      case '':
      default:
        return cartoDarkMatter;
    }
  }

  /// Optional: comma-separated subdomain list when using `{s}` in template.
  /// Defaults to Carto subdomains unless you override via env.
  static List<String> get effectiveSubdomains {
    final raw = dotenv.maybeGet('MAP_TILE_SUBDOMAINS')?.trim();
    if (raw != null && raw.isNotEmpty) {
      return raw
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    final template = effectiveUrlTemplate;
    if (template.contains('{s}') &&
        template.contains('basemaps.cartocdn.com')) {
      return cartoSubdomains;
    }
    return const [];
  }

  /// Short attribution line for UI (Carto presets). If you use a custom
  /// tile URL, set `MAP_TILE_ATTRIBUTION` in env for accuracy.
  static String get attributionLabel {
    final custom = dotenv.maybeGet('MAP_TILE_ATTRIBUTION')?.trim();
    if (custom != null && custom.isNotEmpty) return custom;

    final t = effectiveUrlTemplate;
    if (t.contains('basemaps.cartocdn.com')) {
      return '© OpenStreetMap contributors © CARTO';
    }
    if (t.contains('openstreetmap.org')) {
      return '© OpenStreetMap contributors';
    }
    return 'Map data © respective providers';
  }
}
