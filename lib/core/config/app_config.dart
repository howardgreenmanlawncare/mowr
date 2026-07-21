/// Build-time configuration. Secrets are injected via `--dart-define` and are
/// never committed. See CLAUDE.md ("No inline credentials").
///
/// Run with, e.g.:
///   flutter run \
///     --dart-define=MAPBOX_TOKEN=pk.xxx \
///     --dart-define=IDEAL_POSTCODES_API_KEY=ak_xxx
///
/// Both are optional in Phase 1: without MAPBOX_TOKEN the maps fall back to
/// free Esri World Imagery; without IDEAL_POSTCODES_API_KEY the postcode lookup
/// returns sample addresses so the flow is still demoable.
abstract final class AppConfig {
  /// Mapbox public access token (`pk....`). Used for satellite tiles.
  static const String mapboxToken =
      String.fromEnvironment('MAPBOX_TOKEN', defaultValue: '');

  /// Ideal Postcodes API key (`ak_...`) for UK postcode -> address lookup.
  static const String idealPostcodesKey =
      String.fromEnvironment('IDEAL_POSTCODES_API_KEY', defaultValue: '');

  /// Supabase project URL. The anon key is public by design (RLS enforces
  /// access), so it's safe to ship in the client; both can still be overridden
  /// via --dart-define for other environments.
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://ypbizskokuxpfdyvdgmg.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InlwYml6c2tva3V4cGZkeXZkZ21nIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQ2NDQzODYsImV4cCI6MjEwMDIyMDM4Nn0.9UX8gJ0sgl18X9_P7CE2PJMpe-sJCGqBPuWtkCKYMW8',
  );

  /// Stripe publishable (test) key — public by design; the secret key lives
  /// only in the Supabase Edge Function, never in the app.
  static const String stripePublishableKey = String.fromEnvironment(
    'STRIPE_PUBLISHABLE_KEY',
    defaultValue:
        'pk_test_51TvhBRGsXT7t60IKJLW9ia0CUXY7gsuOWP173Z6PfUNQJjecF9cLQlsIuJJFEHI2Hr64cdJrE28Ts0sL1zpVzIv100oX3kaW3V',
  );

  static bool get hasMapbox => mapboxToken.isNotEmpty;

  static bool get hasAddressApi => idealPostcodesKey.isNotEmpty;

  static bool get hasSupabase =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static bool get hasStripe => stripePublishableKey.isNotEmpty;
}
