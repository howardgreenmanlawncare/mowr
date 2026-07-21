import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Reason a location request could not be fulfilled, for user-facing messaging.
enum LocationFailure { serviceOff, denied, deniedForever, error }

class LocationResult {
  const LocationResult({this.position, this.failure});
  final LatLng? position;
  final LocationFailure? failure;

  bool get ok => position != null;
}

/// Thin wrapper over geolocator: checks the location service + permission,
/// requesting it if needed, then returns the device's current position.
class LocationService {
  static Future<LocationResult> currentPosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocationResult(failure: LocationFailure.serviceOff);
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        return const LocationResult(failure: LocationFailure.deniedForever);
      }
      if (permission == LocationPermission.denied) {
        return const LocationResult(failure: LocationFailure.denied);
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      return LocationResult(position: LatLng(pos.latitude, pos.longitude));
    } catch (_) {
      return const LocationResult(failure: LocationFailure.error);
    }
  }
}
