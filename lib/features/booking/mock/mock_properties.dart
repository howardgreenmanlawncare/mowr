import '../domain/booking_draft.dart';
import '../domain/lawn_area_model.dart';
import '../domain/property_model.dart';

/// Shared mock properties used by both the saved-properties screen and the
/// lawn-selection screen during Phase 1. Replaced by repository queries in
/// Phase 2. Each property has visibly distinct lawn names and counts so the
/// correct data can be verified by eye.
const kMockProperties = [
  Property(
    id: 'prop-1',
    addressLine1: '14 Meadow View',
    addressCity: 'Chelmsford',
    postcode: 'CM1 1AA',
    lawnAreas: [
      LawnArea(id: 'p1-lawn-1', name: 'Front lawn',   areaSqM: 42, perimeter: 28.5),
      LawnArea(id: 'p1-lawn-2', name: 'Back lawn',    areaSqM: 78, perimeter: 38.2),
      LawnArea(id: 'p1-lawn-3', name: 'Side passage', areaSqM: 12, perimeter: 16.8),
    ],
  ),
  Property(
    id: 'prop-2',
    addressLine1: '7 Orchard Close',
    addressCity: 'Chelmsford',
    postcode: 'CM2 6QR',
    lawnAreas: [
      LawnArea(id: 'p2-lawn-1', name: 'Main garden',    areaSqM: 64, perimeter: 34.0),
      LawnArea(id: 'p2-lawn-2', name: 'Driveway strip', areaSqM: 18, perimeter: 19.4),
    ],
  ),
  Property(
    id: 'prop-3',
    addressLine1: '2 The Green',
    addressCity: 'Writtle',
    postcode: 'CM1 3DT',
    lawnAreas: [
      LawnArea(id: 'p3-lawn-1', name: 'Rear courtyard', areaSqM: 22, perimeter: 20.0),
    ],
  ),
];

/// Looks up a property by [propertyId]. Falls back to the first mock property
/// when no ID is set (e.g. direct navigation without going through properties
/// screen). Replaced by a repository call in Phase 2.
Property mockPropertyById(String? propertyId) {
  if (propertyId == null) return kMockProperties.first;
  return kMockProperties.firstWhere(
    (p) => p.id == propertyId,
    orElse: () => kMockProperties.first,
  );
}

/// The single source of truth for "which lawns belong to this booking",
/// spanning BOTH entry paths (see CLAUDE.md "Screen wiring"):
///
/// - Returning-customer path: a [propertyId] is set, so the property's saved
///   lawns are returned (plus any added in-flow on the guest sub-flow).
/// - Guest path: no [propertyId]; the lawns the customer created in the flow
///   ([BookingDraft.draftLawns]) are the booking's lawns.
///
/// Downstream screens (lawn selection, grass height, condition photos) MUST
/// resolve lawns through this function rather than calling [mockPropertyById]
/// directly, so the guest path and returning path share one contract.
/// In Phase 2 this becomes a per-property repository query.
List<LawnArea> resolveBookingLawns(BookingDraft draft) {
  final base = draft.propertyId != null
      ? mockPropertyById(draft.propertyId).lawnAreas
      : const <LawnArea>[];
  return [...base, ...draft.draftLawns];
}
