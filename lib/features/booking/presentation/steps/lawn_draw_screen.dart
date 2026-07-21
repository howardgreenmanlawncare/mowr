import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/map/satellite_tiles.dart';
import '../../domain/geo_point.dart';
import '../../domain/lawn_area_model.dart';
import '../../domain/lawn_geometry.dart';
import '../../providers/booking_draft_provider.dart';

/// Full-screen map for tracing a single lawn boundary. On "Done" it asks for a
/// name, saves the lawn to the draft, and returns to the lawn list.
class LawnDrawScreen extends ConsumerStatefulWidget {
  const LawnDrawScreen({super.key});

  static const routePath = '/booking/lawn/draw';

  @override
  ConsumerState<LawnDrawScreen> createState() => _LawnDrawScreenState();
}

class _LawnDrawScreenState extends ConsumerState<LawnDrawScreen> {
  final _mapController = MapController();
  final List<LatLng> _points = [];
  late final LatLng _initialCentre;
  late final double _initialZoom;

  @override
  void initState() {
    super.initState();
    final d = ref.read(bookingDraftProvider);
    if (d.propertyLat != null && d.propertyLng != null) {
      _initialCentre = LatLng(d.propertyLat!, d.propertyLng!);
      _initialZoom = usingFallbackImagery ? 19.0 : 20.0;
    } else {
      _initialCentre = const LatLng(52.5, -1.5);
      _initialZoom = 6.0;
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  List<GeoPoint> get _geo =>
      _points.map((p) => GeoPoint(p.latitude, p.longitude)).toList();

  bool get _closed => _points.length >= 3;

  Future<void> _finish() async {
    if (!_closed) return;
    final count = ref.read(bookingDraftProvider).draftLawns.length;
    final defaultName = 'Lawn ${count + 1}';
    final name = await _askLawnName(context, defaultName);
    if (name == null || !mounted) return; // cancelled
    final boundary = _geo;
    ref.read(bookingDraftProvider.notifier).addDraftLawn(
          LawnArea(
            id: 'draft-lawn-${DateTime.now().microsecondsSinceEpoch}',
            name: name.trim().isEmpty ? defaultName : name.trim(),
            areaSqM: areaSquareMetres(boundary),
            perimeter: perimeterMetres(boundary),
            boundary: boundary,
            source: LawnMeasurementSource.drawn,
          ),
        );
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final maxZoom = usingFallbackImagery ? 19.0 : 22.0;
    final area = _closed ? areaSquareMetres(_geo) : 0.0;
    final perimeter = _closed ? perimeterMetres(_geo) : 0.0;

    return Scaffold(
      appBar: AppBar(title: const Text('Draw your lawn')),
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
                    Polyline(
                      points: _points,
                      strokeWidth: 3,
                      color: cs.primary,
                    ),
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
            onPressed: _closed ? _finish : null,
            icon: const Icon(Icons.check_rounded),
            label: Text(_closed ? 'Done — name this lawn' : 'Trace at least 3 corners'),
          ),
        ),
      ),
    );
  }
}

/// Name prompt shown after the boundary is drawn. Returns the chosen name, or
/// null if cancelled. Uses TextButtons (not FilledButton) so the app's
/// full-width button theme can't force an infinite width inside the dialog.
Future<String?> _askLawnName(BuildContext context, String initial) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Name this lawn'),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(hintText: 'e.g. Back lawn'),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, controller.text),
          child: const Text('Save lawn'),
        ),
      ],
    ),
  );
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
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 8,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${area.toStringAsFixed(0)} m²',
              style: const TextStyle(
                  fontWeight: FontWeight.w900, fontSize: 18)),
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
          child: Icon(
            icon,
            color: onTap == null ? Colors.grey.shade400 : cs.primary,
          ),
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
          color: Theme.of(context).colorScheme.primary,
          width: 3,
        ),
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
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 10),
      ),
    );
  }
}
