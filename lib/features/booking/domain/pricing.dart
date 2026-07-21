import 'dart:math' as math;

import 'booking_draft.dart' show GrassLength;
import 'lawn_area_model.dart';

/// The tunable inputs to the pricing formula. Every value here is a "field" the
/// product owner can change (and, in Phase 2+, edit from the admin area without
/// a code change). Defaults are starting figures — adjust freely.
///
/// One turn-up charge and one minimum apply PER VISIT (not per lawn):
///   Mowing = max( turnUp + Σ(ratePerSqm × area × heightMultiplier) , minimum )
///   Edging = max( turnUp + Σ(ratePerMetre × perimeter)             , minimum )
/// Edging only applies to lawns the customer chose to edge.
class PricingRules {
  const PricingRules({
    this.mowTurnUpCharge = 12.0,
    this.mowRatePerSqm = 0.15,
    this.mowMinimumCharge = 20.0,
    this.edgeTurnUpCharge = 6.0,
    this.edgeRatePerMetre = 0.40,
    this.edgeMinimumCharge = 10.0,
    this.heightMultiplierLow = 1.0,
    this.heightMultiplierMedium = 1.6,
    this.heightMultiplierHigh = 2.0,
    this.currencySymbol = '£',
  });

  final double mowTurnUpCharge;
  final double mowRatePerSqm;
  final double mowMinimumCharge;

  final double edgeTurnUpCharge;
  final double edgeRatePerMetre;
  final double edgeMinimumCharge;

  final double heightMultiplierLow;
  final double heightMultiplierMedium;
  final double heightMultiplierHigh;

  final String currencySymbol;

  double heightMultiplier(GrassLength height) => switch (height) {
        GrassLength.low => heightMultiplierLow,
        GrassLength.medium => heightMultiplierMedium,
        GrassLength.high => heightMultiplierHigh,
      };

  PricingRules copyWith({
    double? mowTurnUpCharge,
    double? mowRatePerSqm,
    double? mowMinimumCharge,
    double? edgeTurnUpCharge,
    double? edgeRatePerMetre,
    double? edgeMinimumCharge,
    double? heightMultiplierLow,
    double? heightMultiplierMedium,
    double? heightMultiplierHigh,
    String? currencySymbol,
  }) {
    return PricingRules(
      mowTurnUpCharge: mowTurnUpCharge ?? this.mowTurnUpCharge,
      mowRatePerSqm: mowRatePerSqm ?? this.mowRatePerSqm,
      mowMinimumCharge: mowMinimumCharge ?? this.mowMinimumCharge,
      edgeTurnUpCharge: edgeTurnUpCharge ?? this.edgeTurnUpCharge,
      edgeRatePerMetre: edgeRatePerMetre ?? this.edgeRatePerMetre,
      edgeMinimumCharge: edgeMinimumCharge ?? this.edgeMinimumCharge,
      heightMultiplierLow: heightMultiplierLow ?? this.heightMultiplierLow,
      heightMultiplierMedium:
          heightMultiplierMedium ?? this.heightMultiplierMedium,
      heightMultiplierHigh: heightMultiplierHigh ?? this.heightMultiplierHigh,
      currencySymbol: currencySymbol ?? this.currencySymbol,
    );
  }
}

/// Sensible starting rules. Replaced by DB-backed rules in Phase 2.
const PricingRules kDefaultPricingRules = PricingRules();

/// One lawn's variable contribution to a subtotal (excludes the shared
/// turn-up charge, which is billed once for the whole visit).
class PriceLine {
  const PriceLine({
    required this.lawnId,
    required this.name,
    required this.amount,
    required this.detail,
  });

  final String lawnId;
  final String name;
  final double amount;

  /// e.g. "78 m² · medium grass" or "38.2 m edge".
  final String detail;
}

/// A fully priced booking. Turn-up + variable lines + a minimum floor, computed
/// once per visit for mowing and once for edging.
class BookingQuote {
  const BookingQuote({
    required this.mowTurnUp,
    required this.mowLines,
    required this.mowMinimum,
    required this.edgeTurnUp,
    required this.edgeLines,
    required this.edgeMinimum,
    required this.currencySymbol,
  });

  final double mowTurnUp;
  final List<PriceLine> mowLines;
  final double mowMinimum;

  final double edgeTurnUp;
  final List<PriceLine> edgeLines;
  final double edgeMinimum;

  final String currencySymbol;

  bool get hasMowing => mowLines.isNotEmpty;
  bool get hasEdging => edgeLines.isNotEmpty;

  double get mowVariable => mowLines.fold(0.0, (s, l) => s + l.amount);
  double get edgeVariable => edgeLines.fold(0.0, (s, l) => s + l.amount);

  double get _mowRaw => mowTurnUp + mowVariable;
  double get _edgeRaw => edgeTurnUp + edgeVariable;

  double get mowingSubtotal =>
      hasMowing ? math.max(_mowRaw, mowMinimum) : 0.0;
  double get edgingSubtotal =>
      hasEdging ? math.max(_edgeRaw, edgeMinimum) : 0.0;

  bool get mowMinimumApplied => hasMowing && _mowRaw < mowMinimum;
  bool get edgeMinimumApplied => hasEdging && _edgeRaw < edgeMinimum;

  double get total => mowingSubtotal + edgingSubtotal;

  String money(double value) => '$currencySymbol${value.toStringAsFixed(2)}';
}

/// The single place all price calculation happens (see CLAUDE.md:
/// "Pricing is central"). Nothing else should compute prices.
class PricingEngine {
  const PricingEngine(this.rules);

  final PricingRules rules;

  /// One lawn's variable mowing amount (rate × area × height multiplier).
  double mowVariableFor(LawnArea lawn, GrassLength height) =>
      rules.mowRatePerSqm * lawn.areaSqM * rules.heightMultiplier(height);

  /// One lawn's variable edging amount (rate × perimeter).
  double edgeVariableFor(LawnArea lawn) =>
      rules.edgeRatePerMetre * lawn.perimeter;

  BookingQuote quote({
    required List<LawnArea> lawns,
    required Map<String, GrassLength> heights,
    required Set<String> edgedLawnIds,
  }) {
    final mowLines = <PriceLine>[];
    final edgeLines = <PriceLine>[];

    for (final lawn in lawns) {
      final height = heights[lawn.id] ?? GrassLength.medium;
      mowLines.add(PriceLine(
        lawnId: lawn.id,
        name: lawn.name,
        amount: mowVariableFor(lawn, height),
        detail: '${lawn.areaSqM.toStringAsFixed(0)} m² · '
            '${_heightLabel(height)} grass',
      ));

      if (edgedLawnIds.contains(lawn.id)) {
        edgeLines.add(PriceLine(
          lawnId: lawn.id,
          name: lawn.name,
          amount: edgeVariableFor(lawn),
          detail: '${lawn.perimeter.toStringAsFixed(1)} m edge',
        ));
      }
    }

    return BookingQuote(
      mowTurnUp: rules.mowTurnUpCharge,
      mowLines: mowLines,
      mowMinimum: rules.mowMinimumCharge,
      edgeTurnUp: rules.edgeTurnUpCharge,
      edgeLines: edgeLines,
      edgeMinimum: rules.edgeMinimumCharge,
      currencySymbol: rules.currencySymbol,
    );
  }
}

String _heightLabel(GrassLength height) => switch (height) {
      GrassLength.low => 'short',
      GrassLength.medium => 'medium',
      GrassLength.high => 'long',
    };
