import 'package:flutter/foundation.dart';

// LawnArea (the domain entity) lives in lawn_area_model.dart.
// The draft holds only selected lawn IDs, not embedded lawn objects.

enum GrassLength { low, medium, high }

enum AccessType { straightforward, restricted, noSideAccess }

enum TimeWindow { morning, afternoon, evening }

/// In-progress booking, persisted in Riverpod across all flow steps.
///
/// [propertyId] and [selectedLawnIds] are set by the returning-customer
/// path (lawn selection screen). The guest path sets them after lawn
/// creation (Phase 2+). Both paths converge at the grass-height step.
///
/// Fields that were flat (lawnAreas enum, lawnSize) have been removed:
/// lawn size and identity now live on the [LawnArea] entity, not here.
@immutable
class BookingDraft {
  const BookingDraft({
    this.postcode,
    this.propertyId,
    this.addressLine1,
    this.addressCity,
    this.accessNotes,
    this.selectedLawnIds = const [],
    this.lawnGrassHeights = const {},
    this.serviceId,
    this.selectedExtraIds = const [],
    this.accessType,
    this.scheduledDate,
    this.timeWindow,
  });

  final String? postcode;

  /// The property being serviced. Set by both entry paths.
  final String? propertyId;

  final String? addressLine1;
  final String? addressCity;
  final String? accessNotes;

  /// IDs of the [LawnArea] entities included in this booking.
  /// Subset of the property's saved lawn areas.
  final List<String> selectedLawnIds;

  /// Per-lawn grass height keyed by lawn ID. Defaults to [GrassLength.medium]
  /// for each selected lawn; set at the grass-height convergence step.
  final Map<String, GrassLength> lawnGrassHeights;

  final String? serviceId;
  final List<String> selectedExtraIds;
  final AccessType? accessType;
  final DateTime? scheduledDate;
  final TimeWindow? timeWindow;

  BookingDraft copyWith({
    String? postcode,
    String? propertyId,
    String? addressLine1,
    String? addressCity,
    String? accessNotes,
    List<String>? selectedLawnIds,
    Map<String, GrassLength>? lawnGrassHeights,
    String? serviceId,
    List<String>? selectedExtraIds,
    AccessType? accessType,
    DateTime? scheduledDate,
    TimeWindow? timeWindow,
  }) {
    return BookingDraft(
      postcode: postcode ?? this.postcode,
      propertyId: propertyId ?? this.propertyId,
      addressLine1: addressLine1 ?? this.addressLine1,
      addressCity: addressCity ?? this.addressCity,
      accessNotes: accessNotes ?? this.accessNotes,
      selectedLawnIds: selectedLawnIds ?? this.selectedLawnIds,
      lawnGrassHeights: lawnGrassHeights ?? this.lawnGrassHeights,
      serviceId: serviceId ?? this.serviceId,
      selectedExtraIds: selectedExtraIds ?? this.selectedExtraIds,
      accessType: accessType ?? this.accessType,
      scheduledDate: scheduledDate ?? this.scheduledDate,
      timeWindow: timeWindow ?? this.timeWindow,
    );
  }
}
