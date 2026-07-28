/// One rung of the performance-based commission ladder (admin-editable).
/// A mower qualifies once they meet ALL thresholds; the lowest qualifying
/// tier's [commissionPct] applies (best-of vs any admin override). See
/// migration 0020.
class CommissionTier {
  const CommissionTier({
    required this.id,
    required this.name,
    required this.minJobs,
    required this.minRating,
    required this.minReviews,
    required this.commissionPct,
    required this.active,
  });

  final String id;
  final String name;
  final int minJobs;
  final double minRating;
  final int minReviews;
  final double commissionPct;
  final bool active;

  double get payoutPct => 100 - commissionPct;

  String get summary =>
      '${commissionPct.toStringAsFixed(0)}% fee · needs $minJobs jobs, '
      '${minRating.toStringAsFixed(1)}★, $minReviews reviews';

  factory CommissionTier.fromJson(Map<String, dynamic> json) => CommissionTier(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        minJobs: (json['min_jobs'] as num?)?.toInt() ?? 0,
        minRating: (json['min_rating'] as num?)?.toDouble() ?? 0,
        minReviews: (json['min_reviews'] as num?)?.toInt() ?? 0,
        commissionPct: (json['commission_pct'] as num?)?.toDouble() ?? 0,
        active: json['active'] as bool? ?? true,
      );
}
