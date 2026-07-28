import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';

import '../config/app_config.dart';
import 'map_load_state.dart';

/// Aerial/satellite tile layer used by the confirm-location and lawn-drawing
/// maps.
///
/// - With a Mapbox token configured: Mapbox `satellite-streets` (labels +
///   imagery, higher max zoom for accurate drawing).
/// - Without one: Esri World Imagery, which needs no API key — good enough for
///   development and demos so the flow runs before billing is set up.
/// Pass [loadState] to drive a [MapLoadingOverlay] — every map should, so the
/// grey tile grid is never shown to the user while imagery is still arriving.
TileLayer satelliteTileLayer({MapLoadState? loadState}) {
  if (AppConfig.hasMapbox) {
    return TileLayer(
      urlTemplate:
          'https://api.mapbox.com/styles/v1/mapbox/satellite-streets-v12/tiles/256/{z}/{x}/{y}@2x?access_token=${AppConfig.mapboxToken}',
      userAgentPackageName: 'com.mowr.app',
      maxNativeZoom: 22,
      tileBuilder: _loadReporter(loadState),
    );
  }
  return TileLayer(
    urlTemplate:
        'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
    userAgentPackageName: 'com.mowr.app',
    maxNativeZoom: 19,
    tileBuilder: _loadReporter(loadState),
  );
}

/// Reports finished tiles to [state] without altering how the tile renders.
TileBuilder? _loadReporter(MapLoadState? state) {
  if (state == null) return null;
  return (context, tileWidget, tile) {
    if (tile.loadFinishedAt != null) {
      // tileBuilder runs during build; defer so we never notify listeners
      // mid-frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        state.reportTileLoaded();
      });
    }
    return tileWidget;
  };
}

/// Attribution string appropriate to whichever tile source is active.
String satelliteAttribution() =>
    AppConfig.hasMapbox ? '© Mapbox © OpenStreetMap' : 'Imagery © Esri';

/// True when running on the free fallback imagery (no Mapbox token).
bool get usingFallbackImagery => !AppConfig.hasMapbox;
