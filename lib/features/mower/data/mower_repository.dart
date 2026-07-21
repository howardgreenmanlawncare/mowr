import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
}

final mowerRepositoryProvider =
    Provider<MowerRepository>((ref) => MowerRepository());
