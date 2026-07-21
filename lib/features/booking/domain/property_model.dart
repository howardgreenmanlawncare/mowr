import 'package:flutter/foundation.dart';
import 'lawn_area_model.dart';

/// A customer's saved property. Lawn areas belong to the property
/// permanently; a booking references a subset of them by ID.
@immutable
class Property {
  const Property({
    required this.id,
    required this.addressLine1,
    required this.addressCity,
    required this.postcode,
    this.lat,
    this.lng,
    this.lawnAreas = const [],
  });

  final String id;
  final String addressLine1;
  final String addressCity;
  final String postcode;

  /// Precise property location, captured on the confirm-location map step.
  final double? lat;
  final double? lng;

  final List<LawnArea> lawnAreas;

  int get lawnCount => lawnAreas.length;

  String get lawnCountLabel =>
      lawnCount == 1 ? '1 lawn' : '$lawnCount lawns';
}
