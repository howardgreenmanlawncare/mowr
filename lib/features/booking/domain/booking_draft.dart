import 'package:flutter/foundation.dart';
import 'lawn_area_model.dart';
import 'property_access_model.dart';

// LawnArea (the domain entity) lives in lawn_area_model.dart.
// The draft holds only selected lawn IDs, not embedded lawn objects.

enum GrassLength { low, medium, high }

enum AccessType { straightforward, restricted, noSideAccess }

enum TimeWindow { any, morning, afternoon, evening }

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
    this.propertyLat,
    this.propertyLng,
    this.draftLawns = const [],
    this.accessNotes,
    this.selectedLawnIds = const [],
    this.lawnGrassHeights = const {},
    this.propertyAccessMap = const {},
    this.lawnConditionPhotos = const {},
    this.serviceId,
    this.selectedExtraIds = const [],
    this.edgedLawnIds = const <String>{},
    this.accessType,
    this.scheduledDate,
    this.asap = true,
    this.timeWindow = TimeWindow.any,
    this.accessProvided,
    this.customerName,
    this.customerEmail,
    this.customerMobile,
  });

  final String? postcode;

  /// The property being serviced. Set by both entry paths.
  final String? propertyId;

  final String? addressLine1;
  final String? addressCity;

  /// Precise location of the property being serviced (guest path). Set on the
  /// confirm-location map step; seeds the lawn-drawing map.
  final double? propertyLat;
  final double? propertyLng;

  /// Lawns created in-flow on the guest path (drawn or entered manually).
  /// The returning-customer path uses saved property lawns instead; see
  /// resolveBookingLawns() in mock/mock_properties.dart.
  final List<LawnArea> draftLawns;

  final String? accessNotes;

  /// IDs of the [LawnArea] entities included in this booking.
  /// Subset of the property's saved lawn areas.
  final List<String> selectedLawnIds;

  /// Per-lawn grass height keyed by lawn ID. Defaults to [GrassLength.medium]
  /// for each selected lawn; set at the grass-height convergence step.
  final Map<String, GrassLength> lawnGrassHeights;

  /// Access information keyed by property ID. Stored per-property so it can
  /// prefill for returning customers (Phase 2+).
  final Map<String, PropertyAccess> propertyAccessMap;

  /// Current-condition photo file paths keyed by lawn ID. Phase-1 local
  /// paths only — not uploaded, not persistent across reinstall.
  final Map<String, List<String>> lawnConditionPhotos;

  final String? serviceId;
  final List<String> selectedExtraIds;

  /// IDs of lawns the customer has chosen to have edged. Per-lawn, like grass
  /// height; empty means no edging.
  final Set<String> edgedLawnIds;

  final AccessType? accessType;

  /// The specific date the customer chose. Ignored when [asap] is true.
  final DateTime? scheduledDate;

  /// True = "as soon as possible" (default); false = use [scheduledDate].
  final bool asap;

  /// Preferred time of day; defaults to [TimeWindow.any].
  final TimeWindow timeWindow;

  /// Access fork (spec §5a). true = access is available without the customer
  /// present (gate open / open frontage); false = the customer will be home to
  /// let the mower in. Null until answered on the schedule step.
  final bool? accessProvided;

  /// Contact details. Email is captured early (lead capture); name + mobile are
  /// filled in at account creation / payment.
  final String? customerName;
  final String? customerEmail;
  final String? customerMobile;

  BookingDraft copyWith({
    String? postcode,
    String? propertyId,
    String? addressLine1,
    String? addressCity,
    double? propertyLat,
    double? propertyLng,
    List<LawnArea>? draftLawns,
    String? accessNotes,
    List<String>? selectedLawnIds,
    Map<String, GrassLength>? lawnGrassHeights,
    Map<String, PropertyAccess>? propertyAccessMap,
    Map<String, List<String>>? lawnConditionPhotos,
    String? serviceId,
    List<String>? selectedExtraIds,
    Set<String>? edgedLawnIds,
    AccessType? accessType,
    DateTime? scheduledDate,
    bool? asap,
    TimeWindow? timeWindow,
    bool? accessProvided,
    String? customerName,
    String? customerEmail,
    String? customerMobile,
  }) {
    return BookingDraft(
      postcode: postcode ?? this.postcode,
      propertyId: propertyId ?? this.propertyId,
      addressLine1: addressLine1 ?? this.addressLine1,
      addressCity: addressCity ?? this.addressCity,
      propertyLat: propertyLat ?? this.propertyLat,
      propertyLng: propertyLng ?? this.propertyLng,
      draftLawns: draftLawns ?? this.draftLawns,
      accessNotes: accessNotes ?? this.accessNotes,
      selectedLawnIds: selectedLawnIds ?? this.selectedLawnIds,
      lawnGrassHeights: lawnGrassHeights ?? this.lawnGrassHeights,
      propertyAccessMap: propertyAccessMap ?? this.propertyAccessMap,
      lawnConditionPhotos: lawnConditionPhotos ?? this.lawnConditionPhotos,
      serviceId: serviceId ?? this.serviceId,
      selectedExtraIds: selectedExtraIds ?? this.selectedExtraIds,
      edgedLawnIds: edgedLawnIds ?? this.edgedLawnIds,
      accessType: accessType ?? this.accessType,
      scheduledDate: scheduledDate ?? this.scheduledDate,
      asap: asap ?? this.asap,
      timeWindow: timeWindow ?? this.timeWindow,
      accessProvided: accessProvided ?? this.accessProvided,
      customerName: customerName ?? this.customerName,
      customerEmail: customerEmail ?? this.customerEmail,
      customerMobile: customerMobile ?? this.customerMobile,
    );
  }
}
