import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/commission_status.dart';
import '../domain/mower_account.dart';
import '../domain/mower_earnings.dart';
import '../domain/mower_job.dart';

/// Mower-side data access. All marketplace reads/writes go through the secure
/// server-side functions (available_jobs / my_jobs / accept_job) so customer
/// data is never exposed directly.
class MowerRepository {
  SupabaseClient get _client => Supabase.instance.client;

  List<MowerJob> _parse(dynamic res) {
    final list = (res as List?) ?? const [];
    return list
        .map((e) => MowerJob.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<List<MowerJob>> availableJobs() async =>
      _parse(await _client.rpc('available_jobs'));

  Future<List<MowerJob>> myJobs() async =>
      _parse(await _client.rpc('my_jobs'));

  /// Completed jobs (moved out of "my jobs" once done).
  Future<List<MowerJob>> jobHistory() async =>
      _parse(await _client.rpc('my_job_history'));

  /// Home dashboard stats: today's earnings/jobs, week earnings, available
  /// count, and the mower's current active job (if any).
  Future<Map<String, dynamic>> dashboard() async {
    final res = await _client.rpc('mower_dashboard');
    return Map<String, dynamic>.from(res as Map);
  }

  /// Returns true if this mower won the job, false if another mower got it
  /// first (or it's no longer available).
  Future<bool> acceptJob(String bookingId) async {
    final res =
        await _client.rpc('accept_job', params: {'p_booking_id': bookingId});
    return res == true;
  }

  /// Marks the signed-in user as a mower (pending approval).
  Future<void> registerAsMower() async {
    final id = _client.auth.currentUser?.id;
    if (id == null) return;
    await _client.from('profiles').update({'role': 'mower'}).eq('id', id);
  }

  /// Full detail for one job (assigned mower only).
  Future<Map<String, dynamic>> jobDetail(String bookingId) async {
    final res =
        await _client.rpc('job_detail', params: {'p_booking_id': bookingId});
    return Map<String, dynamic>.from(res as Map);
  }

  /// Advance a job (en_route | arrived | in_progress). Completion goes through
  /// [capturePayment] instead, which also captures the money.
  Future<void> setStatus(String bookingId, String status) async {
    await _client.rpc('set_job_status',
        params: {'p_booking_id': bookingId, 'p_status': status});
  }

  /// Submit corrected on-site measurements. The server reprices from
  /// pricing_rules and returns a summary:
  ///   { mode, original_total, revised_total, delta, pct, threshold_pct,
  ///     approval_status, requires_approval }
  /// [lawns] = [{ 'lawn_area_id': .., 'area_sqm': .., 'perimeter': .. }, ...]
  ///
  /// [mode] = 'reprice'   — reprice THIS visit (permanent lawn untouched), or
  ///          'next_time' — keep this visit's price as booked, but write the
  ///                        corrected size to the property so FUTURE bookings
  ///                        price correctly.
  Future<Map<String, dynamic>> reviseMeasurements(
    String bookingId,
    List<Map<String, dynamic>> lawns, {
    String mode = 'reprice',
  }) async {
    final res = await _client.rpc('revise_job_measurements', params: {
      'p_booking_id': bookingId,
      'p_lawns': lawns,
      'p_mode': mode,
    });
    return Map<String, dynamic>.from(res as Map);
  }

  /// Uploads a before/after photo to storage + records it.
  Future<void> uploadJobPhoto({
    required String bookingId,
    required String kind, // 'before' | 'after'
    required Uint8List bytes,
  }) async {
    final path = '$bookingId/$kind-${DateTime.now().millisecondsSinceEpoch}.jpg';
    await _client.storage.from('job-photos').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(contentType: 'image/jpeg'),
        );
    await _client.from('job_photos').insert({
      'booking_id': bookingId,
      'mower_id': _client.auth.currentUser?.id,
      'kind': kind,
      'storage_path': path,
    });
  }

  /// Captures the held payment and marks the job completed.
  Future<void> capturePayment(String bookingId) async {
    final res = await _client.functions
        .invoke('capture-payment', body: {'booking_id': bookingId});
    final data = res.data;
    if (data is Map && data['ok'] == true) return;
    throw Exception(
        (data is Map ? data['error']?.toString() : null) ?? 'Capture failed.');
  }

  /// Whether the signed-in mower has been approved to take jobs.
  Future<bool> isApproved() async {
    final id = _client.auth.currentUser?.id;
    if (id == null) return false;
    final row = await _client
        .from('profiles')
        .select('mower_approved')
        .eq('id', id)
        .maybeSingle();
    return (row?['mower_approved'] as bool?) ?? false;
  }

  /// The mower's own account state (approval + Connect + commission).
  Future<MowerAccount> mowerAccount() async {
    final res = await _client.rpc('mower_account');
    return MowerAccount.fromJson(Map<String, dynamic>.from(res as Map));
  }

  /// Opt this mower in/out of night-before auto-allocation.
  Future<void> setAutoAllocate(bool on) =>
      _client.rpc('set_auto_allocate', params: {'p_on': on});

  /// Weather per visible job (booking_id → rain risk), from the nightly
  /// weather sweep. Lets the app badge dry vs rain-risk work so a mowr can pick
  /// up dry jobs nearby when their own area is wet. Best-effort — returns an
  /// empty map if the weather feature isn't live yet.
  Future<Map<String, bool>> jobsWeather() async {
    try {
      final res = await _client.rpc('mowr_jobs_weather');
      final out = <String, bool>{};
      for (final e in (res as List? ?? const [])) {
        final m = Map<String, dynamic>.from(e as Map);
        final id = m['booking_id'] as String?;
        if (id != null && m['rain_risk'] != null) {
          out[id] = m['rain_risk'] == true;
        }
      }
      return out;
    } catch (_) {
      return const {};
    }
  }

  /// Release a not-yet-started job back to the pool. If it was auto-allocated,
  /// this is recorded as a refusal; too many auto-accept refusals in 30 days
  /// auto-pauses the mower's auto-accept. Returns
  /// `{ was_auto, refusals_30d, auto_paused, threshold }`.
  Future<Map<String, dynamic>> releaseJob(String bookingId,
      {String? reason}) async {
    final res = await _client.rpc('release_auto_job',
        params: {'p_booking_id': bookingId, 'p_reason': reason});
    return Map<String, dynamic>.from(res as Map);
  }

  /// Cancel a job the mower has already started progressing (accepted →
  /// in_progress). Returns it to the pool and records a reliability event;
  /// cancelling after going en route (address was unlocked) is flagged to admin
  /// as a possible off-app job. Returns
  /// `{ was_visited, refusals_30d, auto_paused }`.
  Future<Map<String, dynamic>> cancelJob(String bookingId,
      {String? reason}) async {
    final res = await _client.rpc('mower_cancel_job',
        params: {'p_booking_id': bookingId, 'p_reason': reason});
    return Map<String, dynamic>.from(res as Map);
  }

  /// The mower's commission standing + what's needed for the next reduction.
  Future<CommissionStatus> commissionStatus() async {
    final res = await _client.rpc('mower_commission_status');
    return CommissionStatus.fromJson(Map<String, dynamic>.from(res as Map));
  }

  /// Starts (or resumes) Stripe Connect onboarding. Returns the hosted URL to
  /// open in the browser.
  Future<String> startConnectOnboarding() async {
    final res = await _client.functions.invoke('connect-onboard');
    final data = res.data;
    final url = data is Map ? data['url']?.toString() : null;
    if (url == null || url.isEmpty) {
      throw Exception(
          (data is Map ? data['error']?.toString() : null) ??
              'Could not start payout setup.');
    }
    return url;
  }

  /// Re-checks Connect status and syncs it server-side. Returns the full status
  /// map: { onboarded, actionRequired, requirement, payoutsEnabled, ... }.
  Future<Map<String, dynamic>> refreshConnectStatus() async {
    final res = await _client.functions.invoke('connect-status');
    final data = res.data;
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }


  /// Stripe balance + next expected payout for the "expected payouts" card.
  /// Returns { exists, available, pending, nextPayout, recent } (amounts pence).
  Future<Map<String, dynamic>> connectBalance() async {
    final res = await _client.functions.invoke('connect-balance');
    final data = res.data;
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  /// Earnings for a date range (inclusive), scoped to the signed-in mower.
  /// Calls the `mower_earnings(p_from, p_to)` function, which returns totals
  /// plus a per-job breakdown.
  Future<MowerEarnings> earnings(DateTime from, DateTime to) async {
    String d(DateTime x) =>
        '${x.year.toString().padLeft(4, '0')}-'
        '${x.month.toString().padLeft(2, '0')}-'
        '${x.day.toString().padLeft(2, '0')}';
    final res = await _client.rpc('mower_earnings',
        params: {'p_from': d(from), 'p_to': d(to)});
    return MowerEarnings.fromJson(Map<String, dynamic>.from(res as Map));
  }

  /// Single-use login link to the mower's Stripe Express dashboard (balance,
  /// payouts, full history).
  Future<String> connectDashboardUrl() async {
    final res = await _client.functions.invoke('connect-dashboard');
    final data = res.data;
    final url = data is Map ? data['url']?.toString() : null;
    if (url == null || url.isEmpty) {
      throw Exception(
          (data is Map ? data['error']?.toString() : null) ??
              'Could not open your Stripe dashboard.');
    }
    return url;
  }
}

final mowerRepositoryProvider =
    Provider<MowerRepository>((ref) => MowerRepository());
