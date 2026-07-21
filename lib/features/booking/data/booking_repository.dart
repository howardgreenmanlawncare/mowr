import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/booking_draft.dart';
import '../domain/lawn_area_model.dart';
import '../domain/pricing.dart';

/// Persists a completed booking: creates the property, its lawns, the booking,
/// and the per-lawn booking rows — all owned by the signed-in customer.
/// Everything else (Phase 1) went through the in-memory draft; this is where it
/// lands in the database.
class BookingRepository {
  SupabaseClient get _client => Supabase.instance.client;

  Future<String> submit({
    required BookingDraft draft,
    required List<LawnArea> lawns,
    required BookingQuote quote,
    String? paymentIntentId,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('Must be signed in to submit a booking.');
    }

    // 1. Property.
    final property = await _client
        .from('properties')
        .insert({
          'customer_id': userId,
          'line1': draft.addressLine1 ?? '',
          'city': draft.addressCity,
          'postcode': draft.postcode,
          'lat': draft.propertyLat,
          'lng': draft.propertyLng,
        })
        .select('id')
        .single();
    final propertyId = property['id'] as String;

    // 2. Lawns — remember each draft lawn's new database id.
    final lawnIdMap = <String, String>{};
    for (final lawn in lawns) {
      final row = await _client
          .from('lawn_areas')
          .insert({
            'property_id': propertyId,
            'name': lawn.name,
            'area_sqm': lawn.areaSqM,
            'perimeter': lawn.perimeter,
            'source': lawn.isDrawn ? 'drawn' : 'manual',
            'boundary': lawn.boundary
                ?.map((p) => {'lat': p.lat, 'lng': p.lng})
                .toList(),
          })
          .select('id')
          .single();
      lawnIdMap[lawn.id] = row['id'] as String;
    }

    // 3. Booking.
    final booking = await _client
        .from('bookings')
        .insert({
          'customer_id': userId,
          'property_id': propertyId,
          'status': 'confirmed',
          'asap': draft.asap,
          'scheduled_date': draft.asap
              ? null
              : draft.scheduledDate?.toIso8601String().substring(0, 10),
          'time_window': draft.timeWindow.name,
          'access_provided': draft.accessProvided,
          'total_amount': quote.total,
          'currency': 'GBP',
          'payment_intent_id': paymentIntentId,
          'payment_status': paymentIntentId != null ? 'authorized' : null,
        })
        .select('id')
        .single();
    final bookingId = booking['id'] as String;

    // 4. Per-lawn booking rows (grass height, edging, price snapshot).
    final mowMap = {for (final l in quote.mowLines) l.lawnId: l.amount};
    final edgeMap = {for (final l in quote.edgeLines) l.lawnId: l.amount};
    final rows = lawns.map((lawn) {
      final height = draft.lawnGrassHeights[lawn.id] ?? GrassLength.medium;
      final edged = draft.edgedLawnIds.contains(lawn.id);
      return {
        'booking_id': bookingId,
        'lawn_area_id': lawnIdMap[lawn.id],
        'grass_height': height.name,
        'edging': edged,
        'mow_price': mowMap[lawn.id],
        'edge_price': edged ? edgeMap[lawn.id] : null,
      };
    }).toList();
    await _client.from('booking_lawns').insert(rows);

    return bookingId;
  }
}

final bookingRepositoryProvider =
    Provider<BookingRepository>((ref) => BookingRepository());
