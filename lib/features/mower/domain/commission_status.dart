/// A mower's commission standing and how far they are from the next reduction.
/// Backed by the `mower_commission_status()` RPC (migration 0020): commission
/// falls as jobs completed, average rating, and review count rise.
class CommissionStatus {
  const CommissionStatus({
    required this.commissionPct,
    required this.jobsCompleted,
    required this.reviewCount,
    this.ratingAvg,
    this.currentTier,
    this.nextTier,
  });

  /// Effective percent MOWR keeps on each job right now (already folds in any
  /// admin override — the best/lowest of override and earned tier wins).
  final double commissionPct;
  final int jobsCompleted;
  final int reviewCount;

  /// Average star rating, or null if they have no reviews yet.
  final double? ratingAvg;

  /// Name of the best tier they currently qualify for, or null (base rate).
  final String? currentTier;

  /// The next reduction to aim for, with the gaps to reach it. Null when they
  /// are already on the lowest tier.
  final NextTier? nextTier;

  double get payoutPct => 100 - commissionPct;

  factory CommissionStatus.fromJson(Map<String, dynamic> json) =>
      CommissionStatus(
        commissionPct: (json['commission_pct'] as num?)?.toDouble() ?? 15,
        jobsCompleted: (json['jobs_completed'] as num?)?.toInt() ?? 0,
        reviewCount: (json['review_count'] as num?)?.toInt() ?? 0,
        ratingAvg: (json['rating_avg'] as num?)?.toDouble(),
        currentTier: json['current_tier'] as String?,
        nextTier: json['next_tier'] == null
            ? null
            : NextTier.fromJson(
                Map<String, dynamic>.from(json['next_tier'] as Map)),
      );
}

/// The next commission tier and what's still needed to unlock it.
class NextTier {
  const NextTier({
    required this.name,
    required this.commissionPct,
    required this.minJobs,
    required this.minRating,
    required this.minReviews,
    required this.jobsNeeded,
    required this.ratingNeeded,
    required this.reviewsNeeded,
  });

  final String name;
  final double commissionPct;
  final int minJobs;
  final double minRating;
  final int minReviews;

  /// Remaining to reach this tier (0 once that requirement is already met).
  final int jobsNeeded;
  final double ratingNeeded;
  final int reviewsNeeded;

  bool get isUnlocked =>
      jobsNeeded == 0 && ratingNeeded <= 0 && reviewsNeeded == 0;

  factory NextTier.fromJson(Map<String, dynamic> json) => NextTier(
        name: json['name'] as String? ?? '',
        commissionPct: (json['commission_pct'] as num?)?.toDouble() ?? 0,
        minJobs: (json['min_jobs'] as num?)?.toInt() ?? 0,
        minRating: (json['min_rating'] as num?)?.toDouble() ?? 0,
        minReviews: (json['min_reviews'] as num?)?.toInt() ?? 0,
        jobsNeeded: (json['jobs_needed'] as num?)?.toInt() ?? 0,
        ratingNeeded: (json['rating_needed'] as num?)?.toDouble() ?? 0,
        reviewsNeeded: (json['reviews_needed'] as num?)?.toInt() ?? 0,
      );
}
