import 'package:flutter/foundation.dart';

/// A latitude/longitude pair (WGS84 degrees). Kept independent of any map
/// package so the domain layer does not depend on flutter_map / latlong2.
@immutable
class GeoPoint {
  const GeoPoint(this.lat, this.lng);

  final double lat;
  final double lng;

  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng};

  factory GeoPoint.fromJson(Map<String, dynamic> json) => GeoPoint(
        (json['lat'] as num).toDouble(),
        (json['lng'] as num).toDouble(),
      );

  @override
  bool operator ==(Object other) =>
      other is GeoPoint && other.lat == lat && other.lng == lng;

  @override
  int get hashCode => Object.hash(lat, lng);
}
