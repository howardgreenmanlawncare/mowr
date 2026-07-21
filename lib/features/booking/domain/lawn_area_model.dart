import 'package:flutter/foundation.dart';

import 'geo_point.dart';

/// How a lawn area's measurements were obtained.
enum LawnMeasurementSource {
  /// Drawn as a polygon on satellite imagery; area + perimeter derived.
  drawn,

  /// Typed in by the customer. Perimeter is low-reliability (see spec) and the
  /// pricing formula must treat it cautiously.
  manual,
}

/// A saved lawn area belonging to a property.
/// Permanent to the property; a booking references a subset by [id].
@immutable
class LawnArea {
  const LawnArea({
    required this.id,
    required this.name,
    required this.areaSqM,
    required this.perimeter,
    this.photoUrl,
    this.boundary,
    this.source = LawnMeasurementSource.manual,
  });

  final String id;
  final String name;

  /// Area in square metres. Derived from [boundary] when drawn, else entered.
  final double areaSqM;

  /// Perimeter in metres. Derived from [boundary] when drawn, else entered.
  final double perimeter;

  /// URL of the permanent per-lawn photo (null until uploaded).
  final String? photoUrl;

  /// The drawn polygon boundary, present only when [source] is
  /// [LawnMeasurementSource.drawn]. Null for manually-entered lawns.
  final List<GeoPoint>? boundary;

  final LawnMeasurementSource source;

  bool get isDrawn => source == LawnMeasurementSource.drawn;

  LawnArea copyWith({
    String? id,
    String? name,
    double? areaSqM,
    double? perimeter,
    String? photoUrl,
    List<GeoPoint>? boundary,
    LawnMeasurementSource? source,
  }) {
    return LawnArea(
      id: id ?? this.id,
      name: name ?? this.name,
      areaSqM: areaSqM ?? this.areaSqM,
      perimeter: perimeter ?? this.perimeter,
      photoUrl: photoUrl ?? this.photoUrl,
      boundary: boundary ?? this.boundary,
      source: source ?? this.source,
    );
  }
}
