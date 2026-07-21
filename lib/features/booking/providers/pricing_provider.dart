import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/pricing.dart';

/// The active pricing rules. Phase 1: the in-code defaults. Phase 2+: overridden
/// by rules loaded from the admin-editable `pricing_rules` table.
final pricingRulesProvider =
    Provider<PricingRules>((ref) => kDefaultPricingRules);

/// The single pricing engine, built from the active rules.
final pricingEngineProvider = Provider<PricingEngine>(
  (ref) => PricingEngine(ref.watch(pricingRulesProvider)),
);
