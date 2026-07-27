import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/booking_draft.dart';
import '../domain/customer_booking.dart';
import '../domain/lawn_area_model.dart';
import '../domain/preferred_mowr.dart';
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
          // 0 = one-off; series_id + occurrence_number default in the DB. The
          // generator cron spawns later occurrences from this.
          'recurrence_interval_days': draft.recurrence.days,
          'access_provided': draft.accessProvided,
          'total_amount': quote.total,
          // Pre-discount subtotal, so the generator applies each occurrence's
          // discount to a clean base rather than compounding.
          'base_amount': quote.subtotal,
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

  static const String _bookingColumns =
      'id, status, asap, scheduled_date, time_window, total_amount, currency, '
      'revised_total, captured_amount, approval_status, created_at, '
      'properties(line1, city, postcode), reviews(rating)';

  /// Whether anyone is signed in. Callers need this to tell "you have no
  /// bookings" apart from "we cannot see your bookings because you are signed
  /// out" — RLS returns an empty list for both, so the query alone cannot.
  bool get isSignedIn => _client.auth.currentUser != null;

  /// The signed-in customer's bookings, newest first. Scoped by the
  /// "bookings: owner all" RLS policy — no client-side customer_id filter is
  /// needed, and adding one would not make it any safer.
  Future<List<CustomerBooking>> myBookings() async {
    final rows = await _client
        .from('bookings')
        .select(_bookingColumns)
        .order('created_at', ascending: false);

    return (rows as List)
        .map((r) => CustomerBooking.fromRow(r as Map<String, dynamic>))
        .toList();
  }

  /// A rough arrival estimate for an active, mower-assigned booking, computed
  /// server-side from the day's plan. Returns null when there's no meaningful
  /// ETA (not yet assigned, or finished). Shape:
  /// `{ eta, minutes_away, underway }`.
  Future<Map<String, dynamic>?> bookingEta(String bookingId) async {
    final res =
        await _client.rpc('booking_eta', params: {'p_booking_id': bookingId});
    return res == null ? null : Map<String, dynamic>.from(res as Map);
  }

  Future<CustomerBooking> booking(String bookingId) async {
    final row = await _client
        .from('bookings')
        .select(_bookingColumns)
        .eq('id', bookingId)
        .single();

    return CustomerBooking.fromRow(row);
  }

  /// Answers a mower's on-site re-measure when the price change was large
  /// enough to need the customer's agreement.
  ///
  /// Approving lets `capture-payment` take the revised amount; declining
  /// leaves the booked price to be settled off-app. The RPC only acts on a
  /// booking whose approval_status is still 'pending', so a double-tap or a
  /// stale screen cannot flip an already-answered revision.
  Future<void> respondToRevision(String bookingId, {required bool approve}) =>
      _client.rpc('respond_to_revision', params: {
        'p_booking_id': bookingId,
        'p_approve': approve,
      });

  // --- Preferred mowrs (migration 0026) -------------------------------------

  /// Adds the mowr who did this completed job to the customer's preferred list.
  /// Returns the mowr's display name. The RPC enforces the job is the caller's,
  /// completed, and has an assigned mowr.
  Future<String> addPreferredMowr(String bookingId) async {
    final res = await _client
        .rpc('add_preferred_mowr', params: {'p_booking_id': bookingId});
    final m = Map<String, dynamic>.from(res as Map);
    return (m['full_name'] as String?) ?? 'your mowr';
  }

  Future<void> removePreferredMowr(String mowrId) =>
      _client.rpc('remove_preferred_mowr', params: {'p_mowr_id': mowrId});

  Future<List<PreferredMowr>> listPreferredMowrs() async {
    final res = await _client.rpc('list_preferred_mowrs');
    return ((res as List?) ?? const [])
        .map((e) => PreferredMowr.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Each preferred mowr's next available date within [days] from today.
  Future<List<MowrAvailability>> preferredMowrAvailability({int days = 21}) async {
    final res = await _client
        .rpc('preferred_mowr_availability', params: {'p_days': days});
    return ((res as List?) ?? const [])
        .map((e) =>
            MowrAvailability.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Moves an upcoming (not-yet-started) booking to a new date/window. The
  /// preference-aware allocator then steers it to a preferred mowr if one fits.
  Future<void> rescheduleBooking(String bookingId, DateTime date,
      {String window = 'any'}) {
    String d(DateTime x) => '${x.year.toString().padLeft(4, '0')}-'
        '${x.month.toString().padLeft(2, '0')}-'
        '${x.day.toString().padLeft(2, '0')}';
    return _client.rpc('reschedule_booking',
        params: {'p_booking_id': bookingId, 'p_date': d(date), 'p_window': window});
  }

  /// Rates a completed job 1–5 (with an optional comment). The `submit_review`
  /// RPC enforces that the booking is the caller's, completed, and unrated, and
  /// stamps the mower from the booking. Feeds the mower's commission tier.
  Future<void> submitReview(String bookingId, int rating, {String? comment}) =>
      _client.rpc('submit_review', params: {
        'p_booking_id': bookingId,
        'p_rating': rating,
        'p_comment': comment,
      });
}

final bookingRepositoryProvider =
    Provider<BookingRepository>((ref) => BookingRepository());
