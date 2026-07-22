import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/map/satellite_tiles.dart';
import '../../booking/domain/geo_point.dart';
import '../../booking/domain/lawn_geometry.dart';

/// Full-screen map for re-tracing a single lawn boundary on site. Pops with the
/// drawn boundary (`List<GeoPoint>`) via Navigator.pop, or null if cancelled.
///
/// Unlike the booking-flow draw screen this is self-contained (no BookingDraft)
/// and returns its result to the caller instead of writing to a provider, so it
/// can be reused by the mower re-measure flow.
class MowerLawnDrawScreen extends StatefulWidget {
  const MowerLawnDrawScreen({
    super.key,
    required this.centre,
    this.lawnName,
  });

  final GeoPoint centre;
  final String? lawnName;

  @override
  State<MowerLawnDrawScreen> createState() => _MowerLawnDrawScreenState();
}

class _MowerLawnDrawScreenState extends State<MowerLawnDrawScreen> {
  final _mapController = MapController();
  final List<LatLng> _points = [];
  late final LatLng _initialCentre;
  late final double _initialZoom;

  @override
  void initState() {
    super.initState();
    _initialCentre = LatLng(widget.centre.lat, widget.centre.lng);
    _initialZoom = usingFallbackImagery ? 19.0 : 20.0;
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  List<GeoPoint> get _geo =>
      _points.map((p) => GeoPoint(p.latitude, p.longitude)).toList();

  bool get _closed => _points.length >= 3;

  void _done() {
    if (!_closed) return;
    Navigator.of(context).pop<List<GeoPoint>>(_geo);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final maxZoom = usingFallbackImagery ? 19.0 : 22.0;
    final area = _closed ? areaSquareMetres(_geo) : 0.0;
    final perimeter = _closed ? perimeterMetres(_geo) : 0.0;

    return Scaffold(
      appBar: AppBar(title: Text(widget.lawnName == null
          ? 'Re-measure lawn'
          : 'Re-measure ${widget.lawnName}')),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _initialCentre,
              initialZoom: _initialZoom,
              minZoom: 3,
              maxZoom: maxZoom,
              onTap: (_, point) => setState(() => _points.add(point)),
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              satelliteTileLayer(),
              if (_closed)
                PolygonLayer(
                  polygons: [
                    Polygon(
                      points: _points,
                      color: cs.primary.withValues(alpha: 0.28),
                      borderColor: cs.primary,
                      borderStrokeWidth: 3,
                    ),
                  ],
                ),
              if (_points.length >= 2 && !_closed)
                PolylineLayer(
                  polylines: [
                    Polyline(points: _points, strokeWidth: 3, color: cs.primary),
                  ],
                ),
              MarkerLayer(
                markers: [
                  for (final p in _points)
                    Marker(
                      point: p,
                      width: 16,
                      height: 16,
                      child: const _VertexDot(),
                    ),
                ],
              ),
            ],
          ),
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: _InfoBar(
              text: _points.isEmpty
                  ? 'Tap each corner of the lawn to trace its edge.'
                  : (_closed
                      ? 'Looking good. Tap Done, or add/adjust points.'
                      : 'Keep tapping the corners — at least 3 needed.'),
            ),
          ),
          if (_closed)
            Positioned(
              top: 62,
              left: 12,
              child: _MeasureBadge(area: area, perimeter: perimeter),
            ),
          Positioned(
            right: 12,
            bottom: 12,
            child: Column(
              children: [
                _RoundButton(
                  icon: Icons.undo_rounded,
                  onTap: _points.isEmpty
                      ? null
                      : () => setState(() => _points.removeLast()),
                ),
                const SizedBox(height: 10),
                _RoundButton(
                  icon: Icons.delete_outline_rounded,
                  onTap: _points.isEmpty ? null : () => setState(_points.clear),
                ),
              ],
            ),
          ),
          Positioned(
            left: 8,
            bottom: 8,
            child: _AttributionChip(text: satelliteAttribution()),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: FilledButton.icon(
            onPressed: _closed ? _done : null,
            icon: const Icon(Icons.check_rounded),
            label: Text(_closed ? 'Use this measurement' : 'Trace at least 3 corners'),
          ),
        ),
      ),
    );
  }
}

class _InfoBar extends StatelessWidget {
  const _InfoBar({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white, fontSize: 13),
      ),
    );
  }
}

class _MeasureBadge extends StatelessWidget {
  const _MeasureBadge({required this.area, required this.perimeter});
  final double area;
  final double perimeter;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${area.toStringAsFixed(0)} m²',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          Text('${perimeter.toStringAsFixed(1)} m edge',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 3,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 46,
          height: 46,
          child: Icon(icon,
              color: onTap == null ? Colors.grey.shade400 : cs.primary),
        ),
      ),
    );
  }
}

class _VertexDot extends StatelessWidget {
  const _VertexDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(
            color: Theme.of(context).colorScheme.primary, width: 3),
      ),
    );
  }
}

class _AttributionChip extends StatelessWidget {
  const _AttributionChip({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text,
          style: const TextStyle(color: Colors.white, fontSize: 10)),
    );
  }
}
