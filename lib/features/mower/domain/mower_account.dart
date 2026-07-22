/// The signed-in mower's own account state (from the `mower_account` RPC).
/// Drives the payout-onboarding UI and the job-gating banners.
class MowerAccount {
  const MowerAccount({
    required this.approved,
    required this.connectOnboarded,
    required this.commissionPct,
    this.connectId,
    this.actionRequired = false,
    this.requirement,
  });

  /// Admin has vetted this mower.
  final bool approved;

  /// Stripe Connect onboarding finished (payouts enabled).
  final bool connectOnboarded;

  /// Percent MOWR keeps on this mower's jobs (per-mower, else the default).
  final double commissionPct;

  /// Stripe Connect account id (acct_…), null until onboarding starts.
  final String? connectId;

  /// Stripe is asking for more info (e.g. a photo ID) to keep payouts enabled.
  final bool actionRequired;

  /// Plain-English description of what Stripe needs, when [actionRequired].
  final String? requirement;

  /// Fully live: can see + accept jobs.
  bool get canWork => approved && connectOnboarded;

  /// What the mower keeps, as a percentage.
  double get payoutPct => 100 - commissionPct;

  factory MowerAccount.fromJson(Map<String, dynamic> json) => MowerAccount(
        approved: json['approved'] as bool? ?? false,
        connectOnboarded: json['connect_onboarded'] as bool? ?? false,
        commissionPct: (json['commission_pct'] as num?)?.toDouble() ?? 15,
        connectId: json['connect_id'] as String?,
        actionRequired: json['connect_action_required'] as bool? ?? false,
        requirement: json['connect_requirement'] as String?,
      );
}
