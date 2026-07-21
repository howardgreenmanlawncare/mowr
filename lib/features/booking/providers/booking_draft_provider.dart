import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/booking_draft.dart';
import '../domain/lawn_area_model.dart';
import '../domain/property_access_model.dart';

class BookingDraftNotifier extends Notifier<BookingDraft> {
  @override
  BookingDraft build() => const BookingDraft();

  void updatePostcode(String postcode) {
    state = state.copyWith(postcode: postcode);
  }

  void updateAddress({
    required String addressLine1,
    required String addressCity,
    String? accessNotes,
  }) {
    state = state.copyWith(
      addressLine1: addressLine1,
      addressCity: addressCity,
      accessNotes: accessNotes,
    );
  }

  /// Guest path: records the chosen address plus the postcode centroid as an
  /// initial location guess (refined on the confirm-location map step).
  /// This is a brand-new property, so [propertyId] stays null — the guest path
  /// is identified by draftLawns / a null propertyId.
  void setGuestAddress({
    required String addressLine1,
    required String addressCity,
    required String postcode,
    double? lat,
    double? lng,
  }) {
    state = state.copyWith(
      addressLine1: addressLine1,
      addressCity: addressCity,
      postcode: postcode,
      propertyLat: lat,
      propertyLng: lng,
    );
  }

  /// Confirm-location step: sets the exact property GPS the customer positioned
  /// under the map pin.
  void setPropertyLocation(double lat, double lng) {
    state = state.copyWith(propertyLat: lat, propertyLng: lng);
  }

  /// Adds a newly created lawn to the guest booking and auto-selects it.
  void addDraftLawn(LawnArea lawn) {
    final lawns = [...state.draftLawns, lawn];
    final selected = [...state.selectedLawnIds, lawn.id];
    state = state.copyWith(
      draftLawns: List.unmodifiable(lawns),
      selectedLawnIds: List.unmodifiable(selected),
    );
  }

  void toggleEdging(String lawnId) {
    final current = Set<String>.from(state.edgedLawnIds);
    if (current.contains(lawnId)) {
      current.remove(lawnId);
    } else {
      current.add(lawnId);
    }
    state = state.copyWith(edgedLawnIds: Set.unmodifiable(current));
  }

  void removeDraftLawn(String lawnId) {
    state = state.copyWith(
      draftLawns:
          List.unmodifiable(state.draftLawns.where((l) => l.id != lawnId)),
      selectedLawnIds: List.unmodifiable(
          state.selectedLawnIds.where((id) => id != lawnId)),
      edgedLawnIds: Set.unmodifiable(
          state.edgedLawnIds.where((id) => id != lawnId)),
    );
  }

  /// Sets the selected property and clears any prior lawn selection so
  /// [initLawnSelection] on the lawn-selection screen starts fresh.
  void setPropertyId(String propertyId) {
    state = state.copyWith(
      propertyId: propertyId,
      selectedLawnIds: const [],
    );
  }

  /// Initialises selection to [allIds] only when [selectedLawnIds] is empty.
  /// Called on lawn-selection screen mount so back-navigation preserves choices.
  void initLawnSelection(List<String> allIds) {
    if (state.selectedLawnIds.isEmpty) {
      state = state.copyWith(selectedLawnIds: List.unmodifiable(allIds));
    }
  }

  void setSelectedLawnIds(List<String> ids) {
    state = state.copyWith(selectedLawnIds: List.unmodifiable(ids));
  }

  void toggleLawnSelection(String lawnId) {
    final current = List<String>.from(state.selectedLawnIds);
    if (current.contains(lawnId)) {
      current.remove(lawnId);
    } else {
      current.add(lawnId);
    }
    state = state.copyWith(selectedLawnIds: List.unmodifiable(current));
  }

  /// Sets each lawn in [lawnIds] to [GrassLength.medium] only if it has no
  /// existing entry — preserves values the user already set on back-navigation.
  void initGrassHeights(List<String> lawnIds) {
    final updated = Map<String, GrassLength>.from(state.lawnGrassHeights);
    var changed = false;
    for (final id in lawnIds) {
      if (!updated.containsKey(id)) {
        updated[id] = GrassLength.medium;
        changed = true;
      }
    }
    if (changed) {
      state = state.copyWith(lawnGrassHeights: Map.unmodifiable(updated));
    }
  }

  void setLawnGrassHeight(String lawnId, GrassLength height) {
    final updated = Map<String, GrassLength>.from(state.lawnGrassHeights);
    updated[lawnId] = height;
    state = state.copyWith(lawnGrassHeights: Map.unmodifiable(updated));
  }

  /// Creates a default [PropertyAccess] entry for [state.propertyId] only if
  /// none exists — preserves any values already set on back-navigation.
  void initPropertyAccess() {
    final propertyId = state.propertyId;
    if (propertyId == null) return;
    if (state.propertyAccessMap.containsKey(propertyId)) return;
    final updated = Map<String, PropertyAccess>.from(state.propertyAccessMap);
    updated[propertyId] = const PropertyAccess();
    state = state.copyWith(propertyAccessMap: Map.unmodifiable(updated));
  }

  void toggleAccessPreset(AccessPreset preset) {
    final propertyId = state.propertyId;
    if (propertyId == null) return;
    final current =
        state.propertyAccessMap[propertyId] ?? const PropertyAccess();
    final presets = Set<AccessPreset>.from(current.presets);
    if (presets.contains(preset)) {
      presets.remove(preset);
    } else {
      presets.add(preset);
    }
    final updated = Map<String, PropertyAccess>.from(state.propertyAccessMap);
    updated[propertyId] =
        current.copyWith(presets: Set.unmodifiable(presets));
    state = state.copyWith(propertyAccessMap: Map.unmodifiable(updated));
  }

  void updateAccessNotes(String notes) {
    final propertyId = state.propertyId;
    if (propertyId == null) return;
    final current =
        state.propertyAccessMap[propertyId] ?? const PropertyAccess();
    final updated = Map<String, PropertyAccess>.from(state.propertyAccessMap);
    updated[propertyId] = current.copyWith(notes: notes);
    state = state.copyWith(propertyAccessMap: Map.unmodifiable(updated));
  }

  void addConditionPhoto(String lawnId, String filePath) {
    final updated =
        Map<String, List<String>>.from(state.lawnConditionPhotos);
    final existing = List<String>.from(updated[lawnId] ?? const []);
    existing.add(filePath);
    updated[lawnId] = List.unmodifiable(existing);
    state =
        state.copyWith(lawnConditionPhotos: Map.unmodifiable(updated));
  }

  void removeConditionPhoto(String lawnId, String filePath) {
    final updated =
        Map<String, List<String>>.from(state.lawnConditionPhotos);
    final existing = List<String>.from(updated[lawnId] ?? const []);
    existing.remove(filePath);
    updated[lawnId] = List.unmodifiable(existing);
    state =
        state.copyWith(lawnConditionPhotos: Map.unmodifiable(updated));
  }

  void updateService({
    required String serviceId,
    required List<String> selectedExtraIds,
    required AccessType accessType,
  }) {
    state = state.copyWith(
      serviceId: serviceId,
      selectedExtraIds: selectedExtraIds,
      accessType: accessType,
    );
  }

  void setAsap() => state = state.copyWith(asap: true);

  void setScheduledDate(DateTime date) =>
      state = state.copyWith(asap: false, scheduledDate: date);

  void setTimeWindow(TimeWindow window) =>
      state = state.copyWith(timeWindow: window);

  void setAccessProvided(bool provided) =>
      state = state.copyWith(accessProvided: provided);

  void reset() => state = const BookingDraft();
}

final bookingDraftProvider =
    NotifierProvider<BookingDraftNotifier, BookingDraft>(
  BookingDraftNotifier.new,
);
