// Initialise Supabase once at app startup (Phase 2).
// Call SupabaseInit.init() before runApp.
// Credentials come from environment / build config — never hard-code here.
//
// Usage:
//   final client = Supabase.instance.client;
import 'package:supabase_flutter/supabase_flutter.dart';

abstract final class SupabaseInit {
  static Future<void> init({
    required String url,
    required String anonKey,
  }) async {
    await Supabase.initialize(url: url, anonKey: anonKey);
  }
}
