/// A job as seen by a mower (from the available_jobs / my_jobs functions).
class MowerJob {
  const MowerJob({
    required this.bookingId,
    required this.status,
    required this.asap,
    required this.totalAmount,
    required this.line1,
    required this.lawnCount,
    required this.totalArea,
    this.scheduledDate,
    this.timeWindow,
    this.accessProvided,
    this.city,
    this.postcode,
    this.lat,
    this.lng,
    this.accessNotes,
  });

  final String bookingId;
  final String status;
  final bool asap;
  final double totalAmount;
  final String line1;
  final int lawnCount;
  final double totalArea;
  final DateTime? scheduledDate;
  final String? timeWindow;
  final bool? accessProvided;
  final String? city;
  final String? postcode;
  final double? lat;
  final double? lng;
  final String? accessNotes;

  String get addressLine =>
      [line1, city, postcode].where((s) => (s ?? '').trim().isNotEmpty).join(', ');

  String get whenLabel {
    if (asap || scheduledDate == null) return 'As soon as possible';
    final d = scheduledDate!;
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]}';
  }

  factory MowerJob.fromJson(Map<String, dynamic> json) {
    double toD(dynamic v) => v == null ? 0 : (v as num).toDouble();
    return MowerJob(
      bookingId: json['booking_id'] as String,
      status: json['status'] as String? ?? 'confirmed',
      asap: json['asap'] as bool? ?? true,
      totalAmount: toD(json['total_amount']),
      line1: json['line1'] as String? ?? '',
      city: json['city'] as String?,
      postcode: json['postcode'] as String?,
      lat: (json['lat'] as num?)?.toDouble(),
      lng: (json['lng'] as num?)?.toDouble(),
      accessNotes: json['access_notes'] as String?,
      timeWindow: json['time_window'] as String?,
      accessProvided: json['access_provided'] as bool?,
      lawnCount: (json['lawn_count'] as num?)?.toInt() ?? 0,
      totalArea: toD(json['total_area']),
      scheduledDate: json['scheduled_date'] == null
          ? null
          : DateTime.tryParse(json['scheduled_date'] as String),
    );
  }
}
