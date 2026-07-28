/// Loyalty / recurrence discounts, admin-modelled.
///
/// A rule knocks a percentage off a booking when its conditions match — the
/// headline case being "recur and your 3rd mow is 20% off". Rules live in the
/// admin-editable `discount_rules` table; the [PricingEngine] applies the best
/// matching one so all money still flows through the single engine.
class DiscountRule {
  const DiscountRule({
    required this.id,
    required this.name,
    required this.percentOff,
    this.active = true,
    this.recurringOnly = true,
    this.minOccurrence = 1,
    this.ongoing = false,
  });

  final String id;
  final String name;

  /// Percentage off the whole booking (0–100).
  final double percentOff;

  final bool active;

  /// Only rewards recurring bookings (the usual case). When false it can apply
  /// to a one-off too.
  final bool recurringOnly;

  /// The occurrence this starts rewarding (1 = the first mow).
  final int minOccurrence;

  /// true  → applies to every occurrence from [minOccurrence] onward.
  /// false → applies only to occurrence number [minOccurrence] (a one-time
  ///         reward, e.g. "your 3rd mow is 20% off").
  final bool ongoing;

  bool appliesTo({required bool isRecurring, required int occurrence}) {
    if (!active) return false;
    if (recurringOnly && !isRecurring) return false;
    return ongoing ? occurrence >= minOccurrence : occurrence == minOccurrence;
  }

  /// Plain-English summary for the customer / admin list.
  String get summary {
    final pct = percentOff == percentOff.roundToDouble()
        ? percentOff.toStringAsFixed(0)
        : percentOff.toStringAsFixed(1);
    final where = ongoing
        ? 'every mow from #$minOccurrence'
        : 'mow #$minOccurrence';
    return '$pct% off $where${recurringOnly ? ' (recurring)' : ''}';
  }

  factory DiscountRule.fromJson(Map<String, dynamic> j) => DiscountRule(
        id: j['id'].toString(),
        name: j['name'] as String? ?? 'Discount',
        percentOff: (j['percent_off'] as num?)?.toDouble() ?? 0,
        active: j['active'] as bool? ?? true,
        recurringOnly: j['recurring_only'] as bool? ?? true,
        minOccurrence: (j['min_occurrence'] as num?)?.toInt() ?? 1,
        ongoing: j['ongoing'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'percent_off': percentOff,
        'active': active,
        'recurring_only': recurringOnly,
        'min_occurrence': minOccurrence,
        'ongoing': ongoing,
      };
}

/// The facts a discount is evaluated against for a specific booking.
class DiscountContext {
  const DiscountContext({required this.isRecurring, required this.occurrence});

  final bool isRecurring;

  /// 1-based occurrence in the recurring series (1 for a one-off).
  final int occurrence;

  static const oneOff = DiscountContext(isRecurring: false, occurrence: 1);
}

/// The best (largest) discount that applies to [context], or null.
DiscountRule? bestDiscount(List<DiscountRule> rules, DiscountContext context) {
  DiscountRule? best;
  for (final r in rules) {
    if (!r.appliesTo(
        isRecurring: context.isRecurring, occurrence: context.occurrence)) {
      continue;
    }
    if (best == null || r.percentOff > best.percentOff) best = r;
  }
  return best;
}

/// The most attractive discount a customer would unlock by recurring — used to
/// advertise the saving at booking time even though occurrence 1 rarely
/// qualifies. Considers any active rule that could ever apply to a recurring
/// series.
DiscountRule? recurringIncentive(List<DiscountRule> rules) {
  DiscountRule? best;
  for (final r in rules) {
    if (!r.active) continue;
    if (best == null || r.percentOff > best.percentOff) best = r;
  }
  return best;
}
