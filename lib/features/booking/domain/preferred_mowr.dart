/// A mowr the customer has chosen to keep — future bookings are steered to
/// their preferred mowrs first (see migration 0026).
class PreferredMowr {
  const PreferredMowr({
    required this.mowrId,
    required this.fullName,
    this.jobs = 0,
  });

  final String mowrId;
  final String fullName;
  final int jobs; // completed jobs this mowr has done for the customer

  factory PreferredMowr.fromJson(Map<String, dynamic> j) => PreferredMowr(
        mowrId: j['mowr_id'] as String,
        fullName: (j['full_name'] as String?) ?? 'Your mowr',
        jobs: (j['jobs'] as num?)?.toInt() ?? 0,
      );
}

/// A preferred mowr's next free date, so the customer can reschedule to them.
class MowrAvailability {
  const MowrAvailability({
    required this.mowrId,
    required this.fullName,
    this.nextAvailable,
  });

  final String mowrId;
  final String fullName;
  final DateTime? nextAvailable;

  factory MowrAvailability.fromJson(Map<String, dynamic> j) => MowrAvailability(
        mowrId: j['mowr_id'] as String,
        fullName: (j['full_name'] as String?) ?? 'Your mowr',
        nextAvailable: j['next_available'] == null
            ? null
            : DateTime.tryParse(j['next_available'].toString()),
      );
}
