import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/discount.dart';
import '../domain/pricing.dart';

/// The active pricing rules.
///
/// Seeded with the in-code defaults so the app can always price something, then
/// overwritten at startup by [loadPricingRules] with the admin-editable
/// `pricing_rules` row — the single source of truth. The admin settings screen
/// writes here too, so an edit takes effect on the next quote without a
/// restart.
///
/// Deliberately a synchronous [StateProvider]: pricing is read during build on
/// several booking steps, and making it async would push loading states into
/// screens that have no useful way to handle "price not known yet".
final pricingRulesProvider =
    StateProvider<PricingRules>((ref) => kDefaultPricingRules);

/// Active loyalty/recurrence discount rules, seeded empty and filled at startup
/// by [loadDiscountRules] from the admin-editable `discount_rules` table.
final discountRulesProvider =
    StateProvider<List<DiscountRule>>((ref) => const []);

/// The single pricing engine, rebuilt whenever the rules or discounts change.
final pricingEngineProvider = Provider<PricingEngine>(
  (ref) => PricingEngine(
    ref.watch(pricingRulesProvider),
    discountRules: ref.watch(discountRulesProvider),
  ),
);

/// Loads the live rates into [pricingRulesProvider]. Call once at startup.
///
/// Best-effort: `pricing_rules` is world-readable, but if the row or the
/// network is unavailable we keep the in-code defaults rather than blocking
/// the app — a quote from slightly stale rates beats no app at all.
Future<void> loadPricingRules(ProviderContainer container) async {
  try {
    // Timed: this runs before runApp(), so an unreachable backend must not be
    // able to hold the app on the splash screen indefinitely.
    final row = await Supabase.instance.client
        .from('pricing_rules')
        .select()
        .eq('id', 1)
        .maybeSingle()
        .timeout(const Duration(seconds: 5));
    if (row == null) return;
    container.read(pricingRulesProvider.notifier).state =
        pricingRulesFromRow(row);
  } catch (_) {
    // Keep the defaults.
  }
}

/// Loads active discount rules into [discountRulesProvider]. Call once at
/// startup. Best-effort — no discounts is a fine fallback.
Future<void> loadDiscountRules(ProviderContainer container) async {
  try {
    final rows = await Supabase.instance.client
        .from('discount_rules')
        .select()
        .eq('active', true)
        .timeout(const Duration(seconds: 5));
    container.read(discountRulesProvider.notifier).state = (rows as List)
        .map((r) => DiscountRule.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  } catch (_) {
    // No discounts — fine.
  }
}

/// Maps a `pricing_rules` row onto [PricingRules]. Column names are the
/// database's; field names are the engine's.
PricingRules pricingRulesFromRow(Map<String, dynamic> row) {
  double d(String key, double fallback) =>
      (row[key] as num?)?.toDouble() ?? fallback;

  return PricingRules(
    mowTurnUpCharge: d('mow_turn_up', 12.0),
    mowRatePerSqm: d('mow_rate_per_sqm', 0.15),
    mowMinimumCharge: d('mow_minimum', 20.0),
    edgeTurnUpCharge: d('edge_turn_up', 6.0),
    edgeRatePerMetre: d('edge_rate_per_metre', 0.40),
    edgeMinimumCharge: d('edge_minimum', 10.0),
    heightMultiplierLow: d('height_mult_low', 1.0),
    heightMultiplierMedium: d('height_mult_medium', 1.6),
    heightMultiplierHigh: d('height_mult_high', 2.0),
    currencySymbol: row['currency_symbol'] as String? ?? '£',
  );
}
