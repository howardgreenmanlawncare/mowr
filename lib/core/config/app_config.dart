/// Build-time configuration. Secrets are injected via `--dart-define` and are
/// never committed. See CLAUDE.md ("No inline credentials").
///
/// Run with, e.g.:
///   flutter run \
///     --dart-define=MAPBOX_TOKEN=pk.xxx \
///     --dart-define=IDEAL_POSTCODES_API_KEY=ak_xxx
///
/// Both are optional in Phase 1: without MAPBOX_TOKEN the maps fall back to
/// free Esri World Imagery; without IDEAL_POSTCODES_API_KEY the postcode lookup
/// returns sample addresses so the flow is still demoable.
abstract final class AppConfig {
  /// Mapbox public access token (`pk....`). Used for satellite tiles.
  static const String mapboxToken =
      String.fromEnvironment('MAPBOX_TOKEN', defaultValue: '');

  /// Ideal Postcodes API key (`ak_...`) for UK postcode -> address lookup.
  static const String idealPostcodesKey =
      String.fromEnvironment('IDEAL_POSTCODES_API_KEY', defaultValue: '');

  static bool get hasMapbox => mapboxToken.isNotEmpty;

  static bool get hasAddressApi => idealPostcodesKey.isNotEmpty;
}
