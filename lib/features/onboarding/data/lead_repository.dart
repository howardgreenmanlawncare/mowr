import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Best-effort early lead capture: stores the email (and postcode, if known) in
/// the `leads` table so an abandoned quote can be followed up. Never throws to
/// the caller — a failed lead insert must not block the booking flow.
class LeadRepository {
  Future<void> capture(String email, {String? postcode}) async {
    try {
      await Supabase.instance.client.from('leads').insert({
        'email': email,
        if (postcode != null && postcode.trim().isNotEmpty)
          'postcode': postcode.trim(),
      });
    } catch (_) {
      // Swallow — lead capture is best-effort (offline, table missing, etc.).
    }
  }
}

final leadRepositoryProvider = Provider<LeadRepository>((ref) => LeadRepository());
