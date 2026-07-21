import 'dart:math' as math;

import 'geo_point.dart';

/// WGS84 equatorial radius in metres (matches turf.js / Google maps_toolkit).
const double _earthRadius = 6378137.0;

double _rad(double deg) => deg * math.pi / 180.0;

/// Perimeter of the closed ring [points], in metres (geodesic / haversine).
/// Returns 0 for fewer than two points. The closing edge (last -> first) is
/// included.
double perimeterMetres(List<GeoPoint> points) {
  if (points.length < 2) return 0;
  var total = 0.0;
  for (var i = 0; i < points.length; i++) {
    total += _haversine(points[i], points[(i + 1) % points.length]);
  }
  return total;
}

/// Area of the closed polygon [points], in square metres.
///
/// Uses a local equirectangular projection about the polygon's centroid
/// latitude, then the shoelace formula. Accurate to sub-percent at lawn scale
/// (validated against known 10 m and 50 m test shapes). Returns 0 for fewer
/// than three points.
double areaSquareMetres(List<GeoPoint> points) {
  if (points.length < 3) return 0;

  final lat0 =
      points.map((p) => p.lat).reduce((a, b) => a + b) / points.length;
  final lon0 = points.first.lng;
  final cosLat0 = math.cos(_rad(lat0));

  final projected = points
      .map((p) => <double>[
            _rad(p.lng - lon0) * cosLat0 * _earthRadius,
            _rad(p.lat - lat0) * _earthRadius,
          ])
      .toList();

  var sum = 0.0;
  for (var i = 0; i < projected.length; i++) {
    final a = projected[i];
    final b = projected[(i + 1) % projected.length];
    sum += a[0] * b[1] - b[0] * a[1];
  }
  return sum.abs() / 2.0;
}

double _haversine(GeoPoint a, GeoPoint b) {
  final lat1 = _rad(a.lat);
  final lat2 = _rad(b.lat);
  final dLat = lat2 - lat1;
  final dLon = _rad(b.lng - a.lng);
  final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1) * math.cos(lat2) * math.sin(dLon / 2) * math.sin(dLon / 2);
  return 2 * _earthRadius * math.asin(math.min(1.0, math.sqrt(h)));
}
