import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'core/config/app_config.dart';
import 'core/routing/router.dart';
import 'core/supabase/supabase_client.dart';
import 'core/theme/app_theme.dart';
import 'features/booking/providers/pricing_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (AppConfig.hasSupabase) {
    await SupabaseInit.init(
      url: AppConfig.supabaseUrl,
      anonKey: AppConfig.supabaseAnonKey,
    );
  }
  if (AppConfig.hasStripe) {
    Stripe.publishableKey = AppConfig.stripePublishableKey;
    await Stripe.instance.applySettings();
  }
  final container = ProviderContainer();
  // Pull the admin-editable rates in before the first screen can quote. Best
  // effort — falls back to the in-code defaults if it fails.
  if (AppConfig.hasSupabase) {
    await loadPricingRules(container);
    await loadDiscountRules(container);
  }

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const MowrApp(),
    ),
  );
}

class MowrApp extends StatelessWidget {
  const MowrApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'MOWR',
      theme: AppTheme.light,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        // Bump all text ~10% for readability, while still respecting the
        // device's own accessibility text-size setting. Clamped so very large
        // system settings don't break layouts.
        final mq = MediaQuery.of(context);
        final systemFactor = mq.textScaler.scale(1.0);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: TextScaler.linear(
              (systemFactor * 1.1).clamp(1.0, 1.5),
            ),
          ),
          child: child!,
        );
      },
    );
  }
}
