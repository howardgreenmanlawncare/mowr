import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/location/location_service.dart';
import '../../../../core/map/satellite_tiles.dart';
import '../../providers/booking_draft_provider.dart';
import 'lawn_step.dart';

/// Fallback map centre when we have no postcode centroid (roughly the middle
/// of England), shown zoomed out so the customer can find their area.
const LatLng _kDefaultCentre = LatLng(52.5, -1.5);

/// Full-screen map for pinpointing the property. The map moves under a fixed
/// centre pin; "Confirm location" captures wherever the pin sits. A locate
/// button re-centres on the customer's GPS if they're at the property.
class AddressStepScreen extends ConsumerStatefulWidget {
  const AddressStepScreen({super.key});

  static const routePath = '/booking/address';

  @override
  ConsumerState<AddressStepScreen> createState() => _AddressStepScreenState();
}

class _AddressStepScreenState extends ConsumerState<AddressStepScreen> {
  final _mapController = MapController();
  late final LatLng _initialCentre;
  late final double _initialZoom;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    final draft = ref.read(bookingDraftProvider);
    if (draft.propertyLat != null && draft.propertyLng != null) {
      _initialCentre = LatLng(draft.propertyLat!, draft.propertyLng!);
      _initialZoom = 18.0;
    } else {
      _initialCentre = _kDefaultCentre;
      _initialZoom = 6.0;
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  double get _maxZoom => usingFallbackImagery ? 19.0 : 22.0;

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _useMyLocation() async {
    setState(() => _locating = true);
    final result = await LocationService.currentPosition();
    if (!mounted) return;
    setState(() => _locating = false);
    if (result.ok) {
      _mapController.move(
          result.position!, 18.5.clamp(3.0, _maxZoom).toDouble());
    } else {
      _snack(switch (result.failure) {
        LocationFailure.serviceOff =>
          'Location is turned off on your device. Turn it on, or drag the map '
              'to your property.',
        LocationFailure.deniedForever =>
          'Location permission is blocked. Allow it in Settings, or drag the '
              'map to your property.',
        _ => "Couldn't get your location. Drag the map to your property "
            'instead.',
      });
    }
  }

  void _confirm() {
    final centre = _mapController.camera.center;
    ref
        .read(bookingDraftProvider.notifier)
        .setPropertyLocation(centre.latitude, centre.longitude);
    context.push(LawnStepScreen.routePath);
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(bookingDraftProvider);
    final address = [draft.addressLine1, draft.addressCity, draft.postcode]
        .where((s) => s != null && s.trim().isNotEmpty)
        .join(', ');

    return Scaffold(
      appBar: AppBar(title: const Text('Confirm location')),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _initialCentre,
              initialZoom: _initialZoom,
              minZoom: 3,
              maxZoom: _maxZoom,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              satelliteTileLayer(),
            ],
          ),
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: _InfoBar(
              address: address.isEmpty ? null : address,
            ),
          ),
          const IgnorePointer(child: _CentrePin()),
          Positioned(
            right: 12,
            bottom: 12,
            child: _LocateButton(
              loading: _locating,
              onPressed: _locating ? null : _useMyLocation,
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
            onPressed: _confirm,
            icon: const Icon(Icons.check_rounded),
            label: const Text('Confirm location'),
          ),
        ),
      ),
    );
  }
}

class _InfoBar extends StatelessWidget {
  const _InfoBar({this.address});

  final String? address;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (address != null) ...[
            Text(
              address!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
          ],
          const Text(
            'Drag the map so the pin sits on your property. '
            "Tap ⊕ if you're there now.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _LocateButton extends StatelessWidget {
  const _LocateButton({required this.loading, required this.onPressed});

  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 3,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: 50,
          height: 50,
          child: loading
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(Icons.my_location_rounded, color: cs.primary),
        ),
      ),
    );
  }
}

class _CentrePin extends StatelessWidget {
  const _CentrePin();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.location_on, size: 46, color: cs.primary),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: cs.primary,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1.5),
            ),
          ),
          const SizedBox(height: 46),
        ],
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
