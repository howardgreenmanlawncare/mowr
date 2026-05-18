import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/booking_draft.dart';

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

  void updateSchedule({
    required DateTime scheduledDate,
    required TimeWindow timeWindow,
  }) {
    state = state.copyWith(
      scheduledDate: scheduledDate,
      timeWindow: timeWindow,
    );
  }

  void reset() => state = const BookingDraft();
}

final bookingDraftProvider =
    NotifierProvider<BookingDraftNotifier, BookingDraft>(
  BookingDraftNotifier.new,
);
