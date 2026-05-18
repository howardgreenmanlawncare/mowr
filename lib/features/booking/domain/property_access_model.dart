import 'package:flutter/foundation.dart';

enum AccessPreset {
  frontOpen,
  sideGate,
  lockedGate,
  throughGarage,
  other;

  String get label => switch (this) {
        AccessPreset.frontOpen => 'Front (open access)',
        AccessPreset.sideGate => 'Side gate',
        AccessPreset.lockedGate => 'Locked gate / needs code',
        AccessPreset.throughGarage => 'Through garage',
        AccessPreset.other => 'Other',
      };

  /// Whether this preset triggers the mandatory-notes requirement.
  bool get requiresNotes =>
      this == AccessPreset.lockedGate || this == AccessPreset.other;
}

/// Access information for a specific property.
/// Stored per-property (not per-booking) so it can prefill on return visits.
@immutable
class PropertyAccess {
  const PropertyAccess({
    this.presets = const <AccessPreset>{},
    this.notes = '',
  });

  final Set<AccessPreset> presets;
  final String notes;

  /// True when the selected presets require the customer to fill in notes.
  bool get notesRequired => presets.any((p) => p.requiresNotes);

  PropertyAccess copyWith({Set<AccessPreset>? presets, String? notes}) {
    return PropertyAccess(
      presets: presets ?? this.presets,
      notes: notes ?? this.notes,
    );
  }
}
