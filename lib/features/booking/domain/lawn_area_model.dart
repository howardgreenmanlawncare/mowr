import 'package:flutter/foundation.dart';

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
  });

  final String id;
  final String name;

  /// Area in square metres, captured by boundary drawing (Phase 2+).
  final double areaSqM;

  /// Perimeter in metres.
  final double perimeter;

  /// URL of the permanent per-lawn photo (null until uploaded).
  final String? photoUrl;
}
