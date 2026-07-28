/// A booking as the customer sees it after checkout.
///
/// Read-only view over `bookings` joined to its property. The mower side has
/// its own richer model (`MowerJob`); this one carries only what a customer
/// needs to track a job and respond to a re-measure.
class CustomerBooking {
  const CustomerBooking({
    required this.id,
    required this.status,
    required this.asap,
    required this.currency,
    this.scheduledDate,
    this.timeWindow,
    this.line1,
    this.city,
    this.postcode,
    this.totalAmount,
    this.revisedTotal,
    this.capturedAmount,
    this.approvalStatus = RevisionApproval.notRequired,
    this.createdAt,
    this.myRating,
  });

  final String id;
  final String status;
  final bool asap;
  final String currency;

  final DateTime? scheduledDate;
  final String? timeWindow;

  final String? line1;
  final String? city;
  final String? postcode;

  /// The price quoted and authorised at booking time.
  final double? totalAmount;

  /// Set once a mower has re-measured on site. Null means the booked price
  /// still stands.
  final double? revisedTotal;

  /// What was actually taken, once the job completed.
  final double? capturedAmount;

  final RevisionApproval approvalStatus;
  final DateTime? createdAt;

  /// The star rating this customer left for the job, or null if unrated. Only a
  /// completed job can be rated.
  final int? myRating;

  bool get isCompleted => status == 'completed';

  /// A finished job the customer hasn't rated yet.
  bool get canReview => isCompleted && myRating == null;

  /// The price the customer is being asked to agree to, if any.
  double? get pendingTotal =>
      approvalStatus == RevisionApproval.pending ? revisedTotal : null;

  /// Difference between the revised and booked price. Positive = costs more.
  double? get revisionDelta => (revisedTotal != null && totalAmount != null)
      ? revisedTotal! - totalAmount!
      : null;

  /// True while the job is blocked waiting on the customer. Payment cannot be
  /// captured and the mower cannot complete until this is answered — see
  /// `capture-payment`, which refuses on a pending approval.
  bool get needsResponse => approvalStatus == RevisionApproval.pending;

  bool get isFinished =>
      status == 'completed' || status == 'cancelled' || status == 'expired';

  String get addressLine =>
      [line1, city, postcode].where((p) => p != null && p.isNotEmpty).join(', ');

  static double? _money(dynamic v) => (v as num?)?.toDouble();

  static DateTime? _date(dynamic v) =>
      v == null ? null : DateTime.tryParse(v as String);

  /// Parses a row selected with the property embedded, e.g.
  /// `.select('*, properties(line1, city, postcode)')`.
  factory CustomerBooking.fromRow(Map<String, dynamic> row) {
    final property = row['properties'] as Map<String, dynamic>?;
    // `reviews(rating)` embeds as a list (0 or 1 row under RLS for the customer).
    final reviews = row['reviews'] as List?;
    final int? myRating = (reviews != null && reviews.isNotEmpty)
        ? (reviews.first as Map)['rating'] as int?
        : null;
    return CustomerBooking(
      id: row['id'] as String,
      status: row['status'] as String? ?? 'confirmed',
      asap: row['asap'] as bool? ?? true,
      currency: row['currency'] as String? ?? 'GBP',
      scheduledDate: _date(row['scheduled_date']),
      timeWindow: row['time_window'] as String?,
      line1: property?['line1'] as String?,
      city: property?['city'] as String?,
      postcode: property?['postcode'] as String?,
      totalAmount: _money(row['total_amount']),
      revisedTotal: _money(row['revised_total']),
      capturedAmount: _money(row['captured_amount']),
      approvalStatus: RevisionApproval.parse(row['approval_status'] as String?),
      createdAt: _date(row['created_at']),
      myRating: myRating,
    );
  }
}

/// Mirrors the `bookings.approval_status` check constraint (migration 0006).
enum RevisionApproval {
  notRequired,
  pending,
  approved,
  declined;

  static RevisionApproval parse(String? raw) => switch (raw) {
        'pending' => RevisionApproval.pending,
        'approved' => RevisionApproval.approved,
        'declined' => RevisionApproval.declined,
        _ => RevisionApproval.notRequired,
      };
}
