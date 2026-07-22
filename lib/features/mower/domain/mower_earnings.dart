/// A mower's earnings for a date range, from the `mower_earnings` RPC.
///
/// Shape returned by the function:
///   { from, to,
///     totals: { jobs, gross, fees, net },
///     jobs:   [ { booking_id, completed_date, completed_at, line1, city,
///                 postcode, job_total, commission_amount, mower_amount } ] }
class MowerEarnings {
  const MowerEarnings({
    required this.from,
    required this.to,
    required this.jobs,
    required this.gross,
    required this.fees,
    required this.net,
    required this.rows,
  });

  /// Inclusive start of the range (date only).
  final DateTime from;

  /// Inclusive end of the range (date only).
  final DateTime to;

  /// Number of completed jobs in the range.
  final int jobs;

  /// Sum of job totals actually charged (pounds).
  final double gross;

  /// Sum of MOWR's commission (pounds).
  final double fees;

  /// Sum of the mower's take-home (pounds).
  final double net;

  /// Per-job rows, newest first.
  final List<EarningsRow> rows;

  factory MowerEarnings.fromJson(Map<String, dynamic> json) {
    double toD(dynamic v) => v == null ? 0 : (v as num).toDouble();
    final totals = (json['totals'] as Map?) ?? const {};
    final rawJobs = (json['jobs'] as List?) ?? const [];
    return MowerEarnings(
      from: DateTime.parse(json['from'] as String),
      to: DateTime.parse(json['to'] as String),
      jobs: (totals['jobs'] as num?)?.toInt() ?? 0,
      gross: toD(totals['gross']),
      fees: toD(totals['fees']),
      net: toD(totals['net']),
      rows: rawJobs
          .map((e) => EarningsRow.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }
}

class EarningsRow {
  const EarningsRow({
    required this.bookingId,
    required this.date,
    required this.line1,
    required this.jobTotal,
    required this.fee,
    required this.net,
    this.city,
    this.postcode,
  });

  final String bookingId;

  /// Completion date (local), ISO `yyyy-MM-dd`.
  final String date;
  final String line1;
  final String? city;
  final String? postcode;

  /// Amount charged for this job (pounds).
  final double jobTotal;

  /// MOWR's commission on this job (pounds).
  final double fee;

  /// The mower's take-home on this job (pounds).
  final double net;

  /// Street + town (postcode is kept separate, as its own CSV column).
  String get address =>
      [line1, city].where((s) => (s ?? '').trim().isNotEmpty).join(', ');

  /// "20 Jul" style label from [date].
  String get dateLabel {
    final d = DateTime.tryParse(date);
    if (d == null) return date;
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]}';
  }

  factory EarningsRow.fromJson(Map<String, dynamic> json) {
    double toD(dynamic v) => v == null ? 0 : (v as num).toDouble();
    return EarningsRow(
      bookingId: json['booking_id'] as String? ?? '',
      date: json['completed_date'] as String? ?? '',
      line1: json['line1'] as String? ?? '',
      city: json['city'] as String?,
      postcode: json['postcode'] as String?,
      jobTotal: toD(json['job_total']),
      fee: toD(json['commission_amount']),
      net: toD(json['mower_amount']),
    );
  }
}
