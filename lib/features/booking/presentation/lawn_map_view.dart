import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/map/map_load_state.dart';
import '../../../core/map/satellite_tiles.dart';
import '../domain/lawn_area_model.dart';

/// Read-only view of a drawn lawn's outline on satellite imagery.
///
/// Opened from the "Your lawns" and edging lists so the customer can confirm
/// which lawn is which. Only meaningful for drawn lawns — a manually-entered
/// lawn has no [LawnArea.boundary] and [canShow] returns false.
class LawnMapView extends StatefulWidget {
  const LawnMapView({super.key, required this.lawn});

  final LawnArea lawn;

  /// Whether there's an outline to show. Manual lawns have no boundary.
  static bool canShow(LawnArea lawn) =>
      lawn.boundary != null && lawn.boundary!.length >= 3;

  /// Opens the view as a full-screen page. No-op if there's nothing to show.
  static Future<void> open(BuildContext context, LawnArea lawn) {
    if (!canShow(lawn)) return Future.value();
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => LawnMapView(lawn: lawn)),
    );
  }

  @override
  State<LawnMapView> createState() => _LawnMapViewState();
}

class _LawnMapViewState extends State<LawnMapView> {
  final _mapLoad = MapLoadState();

  @override
  void dispose() {
    _mapLoad.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final points = widget.lawn.boundary!
        .map((p) => LatLng(p.lat, p.lng))
        .toList();

    return Scaffold(
      appBar: AppBar(title: Text(widget.lawn.name)),
      body: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              // Frame the whole polygon with a little breathing room, rather
              // than guessing a centre and zoom.
              initialCameraFit: CameraFit.coordinates(
                coordinates: points,
                padding: const EdgeInsets.all(48),
                maxZoom: usingFallbackImagery ? 19 : 20,
              ),
              minZoom: 3,
              maxZoom: usingFallbackImagery ? 19 : 22,
              // Read-only: pan/zoom to inspect, but no editing.
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              satelliteTileLayer(loadState: _mapLoad),
              PolygonLayer(
                polygons: [
                  Polygon(
                    points: points,
                    color: cs.primary.withValues(alpha: 0.28),
                    borderColor: cs.primary,
                    borderStrokeWidth: 3,
                  ),
                ],
              ),
            ],
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: _InfoChip(
              text: '${widget.lawn.areaSqM.toStringAsFixed(0)} m²  ·  '
                  '${widget.lawn.perimeter.toStringAsFixed(1)} m edge',
            ),
          ),
          Positioned.fill(
            child: MapLoadingOverlay(state: _mapLoad),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          text,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
