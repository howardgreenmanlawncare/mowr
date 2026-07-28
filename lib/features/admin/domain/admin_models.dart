import '../../booking/domain/pricing.dart';

/// A mower as the admin vetting queue sees them.
class AdminMower {
  const AdminMower({
    required this.id,
    required this.approved,
    required this.connectOnboarded,
    this.phoneVerified = false,
    this.fullName,
    this.email,
    this.phone,
    this.commissionPct,
    this.jobsCompleted = 0,
    this.autoAllocate = false,
    this.refusals30d = 0,
    this.createdAt,
  });

  final String id;

  /// Admin has vetted them. Necessary but not sufficient to take work.
  final bool approved;

  /// Mobile number confirmed by SMS code.
  final bool phoneVerified;

  /// Stripe Connect onboarding finished. Also required before they can accept
  /// a job — see `is_approved_mower()` in migration 0008.
  final bool connectOnboarded;

  final String? fullName;
  final String? email;
  final String? phone;

  /// Null means "use the global default commission".
  final double? commissionPct;

  final int jobsCompleted;

  /// Opted into night-before auto-allocation.
  final bool autoAllocate;

  /// Jobs this mower has dropped in the last 30 days — pre-start refusals plus
  /// cancels after accepting (including bailing after going en route, the
  /// possible off-app-cash signal). A high count is a reliability red flag; the
  /// server auto-pauses auto-accept at 3.
  final int refusals30d;

  final DateTime? createdAt;

  /// Whether this mower's recent auto-accept refusals warrant a flag.
  bool get refusalFlag => refusals30d >= 3;

  /// Whether this mower can actually pick up jobs right now. Mirrors
  /// is_approved_mower() on the server — keep the gates in step.
  bool get canWork => approved && connectOnboarded && phoneVerified;

  /// Why they can't, if they can't — for the UI to explain the blockage rather
  /// than just showing them as inactive. Reports the mower's own outstanding
  /// steps before the admin's approval.
  String? get blockedReason {
    final pending = <String>[
      if (!phoneVerified) 'mobile not verified',
      if (!connectOnboarded) 'payouts not set up',
    ];
    if (pending.isNotEmpty) {
      return '${pending.join(', ')}${!approved ? ', awaiting your approval' : ''}';
    }
    if (!approved) return 'Waiting for your approval';
    return null;
  }

  String get displayName {
    final n = fullName?.trim();
    if (n != null && n.isNotEmpty) return n;
    return email ?? 'Unnamed mower';
  }

  factory AdminMower.fromJson(Map<String, dynamic> j) => AdminMower(
        id: j['id'] as String,
        approved: j['approved'] as bool? ?? false,
        connectOnboarded: j['connect_onboarded'] as bool? ?? false,
        phoneVerified: j['phone_verified'] as bool? ?? false,
        fullName: j['full_name'] as String?,
        email: j['email'] as String?,
        phone: j['phone'] as String?,
        commissionPct: (j['commission_pct'] as num?)?.toDouble(),
        jobsCompleted: (j['jobs_completed'] as num?)?.toInt() ?? 0,
        autoAllocate: j['auto_allocate'] as bool? ?? false,
        refusals30d: (j['refusals_30d'] as num?)?.toInt() ?? 0,
        createdAt: j['created_at'] == null
            ? null
            : DateTime.tryParse(j['created_at'] as String),
      );
}

/// The single global settings row: pricing rates, the re-measure auto-approve
/// threshold, and the default commission.
class AdminSettings {
  const AdminSettings({
    required this.mowTurnUp,
    required this.mowRatePerSqm,
    required this.mowMinimum,
    required this.edgeTurnUp,
    required this.edgeRatePerMetre,
    required this.edgeMinimum,
    required this.heightMultLow,
    required this.heightMultMedium,
    required this.heightMultHigh,
    required this.reviseAutoThresholdPct,
    required this.defaultCommissionPct,
  });

  final double mowTurnUp;
  final double mowRatePerSqm;
  final double mowMinimum;
  final double edgeTurnUp;
  final double edgeRatePerMetre;
  final double edgeMinimum;
  final double heightMultLow;
  final double heightMultMedium;
  final double heightMultHigh;

  /// A re-measure this far above the booked price is captured automatically;
  /// beyond it the customer must approve.
  final double reviseAutoThresholdPct;

  final double defaultCommissionPct;

  static double _d(dynamic v, double fallback) =>
      (v as num?)?.toDouble() ?? fallback;

  factory AdminSettings.fromJson(Map<String, dynamic> j) => AdminSettings(
        mowTurnUp: _d(j['mow_turn_up'], 12),
        mowRatePerSqm: _d(j['mow_rate_per_sqm'], 0.15),
        mowMinimum: _d(j['mow_minimum'], 20),
        edgeTurnUp: _d(j['edge_turn_up'], 6),
        edgeRatePerMetre: _d(j['edge_rate_per_metre'], 0.40),
        edgeMinimum: _d(j['edge_minimum'], 10),
        heightMultLow: _d(j['height_mult_low'], 1.0),
        heightMultMedium: _d(j['height_mult_medium'], 1.6),
        heightMultHigh: _d(j['height_mult_high'], 2.0),
        reviseAutoThresholdPct: _d(j['revise_auto_threshold_pct'], 5),
        defaultCommissionPct: _d(j['default_commission_pct'], 15),
      );

  /// The same numbers in the shape the pricing engine wants, so saving in the
  /// admin screen can update live quoting immediately.
  PricingRules toPricingRules() => PricingRules(
        mowTurnUpCharge: mowTurnUp,
        mowRatePerSqm: mowRatePerSqm,
        mowMinimumCharge: mowMinimum,
        edgeTurnUpCharge: edgeTurnUp,
        edgeRatePerMetre: edgeRatePerMetre,
        edgeMinimumCharge: edgeMinimum,
        heightMultiplierLow: heightMultLow,
        heightMultiplierMedium: heightMultMedium,
        heightMultiplierHigh: heightMultHigh,
      );

  Map<String, dynamic> toPatch() => {
        'mow_turn_up': mowTurnUp,
        'mow_rate_per_sqm': mowRatePerSqm,
        'mow_minimum': mowMinimum,
        'edge_turn_up': edgeTurnUp,
        'edge_rate_per_metre': edgeRatePerMetre,
        'edge_minimum': edgeMinimum,
        'height_mult_low': heightMultLow,
        'height_mult_medium': heightMultMedium,
        'height_mult_high': heightMultHigh,
        'revise_auto_threshold_pct': reviseAutoThresholdPct,
        'default_commission_pct': defaultCommissionPct,
      };
}
