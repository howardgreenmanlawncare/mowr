import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../booking/domain/discount.dart';
import '../domain/commission_tier.dart';
import '../domain/admin_models.dart';

/// Admin-side data: vet mowers, set commission, edit global pricing.
///
/// Every call goes through a SECURITY DEFINER RPC that checks `is_admin()`
/// server-side (migration 0013) — the admin's rights are never assumed from the
/// client. A non-admin calling these gets a Postgres exception, not silence.
class AdminRepository {
  SupabaseClient get _client => Supabase.instance.client;

  Future<List<AdminMower>> listMowers() async {
    final res = await _client.rpc('admin_list_mowers');
    final rows = (res as List?) ?? const [];
    return rows
        .map((r) => AdminMower.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<void> setApproved(String mowerId, {required bool approved}) =>
      _client.rpc('admin_set_mower_approved', params: {
        'p_mower_id': mowerId,
        'p_approved': approved,
      });

  /// Pass null to clear the override and fall back to the global default.
  Future<void> setCommission(String mowerId, double? pct) =>
      _client.rpc('admin_set_commission', params: {
        'p_mower_id': mowerId,
        'p_pct': pct,
      });

  Future<AdminSettings> settings() async {
    final res = await _client.rpc('admin_settings');
    return AdminSettings.fromJson(Map<String, dynamic>.from(res as Map));
  }

  Future<AdminSettings> updateSettings(AdminSettings next) async {
    final res = await _client
        .rpc('admin_update_settings', params: {'p_patch': next.toPatch()});
    return AdminSettings.fromJson(Map<String, dynamic>.from(res as Map));
  }

  Future<List<DiscountRule>> listDiscounts() async {
    final res = await _client.rpc('admin_list_discounts');
    return ((res as List?) ?? const [])
        .map((r) => DiscountRule.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// Upserts a rule. Pass [id] to update an existing one; omit for a new rule.
  Future<void> saveDiscount(DiscountRule rule, {String? id}) =>
      _client.rpc('admin_save_discount', params: {
        'p': {
          'id': id,
          'name': rule.name,
          'percent_off': rule.percentOff,
          'active': rule.active,
          'recurring_only': rule.recurringOnly,
          'min_occurrence': rule.minOccurrence,
          'ongoing': rule.ongoing,
        },
      });

  Future<void> deleteDiscount(String id) =>
      _client.rpc('admin_delete_discount', params: {'p_id': id});

  /// The commission ladder. [mowerId] null → the global defaults; a mower id →
  /// that mower's own bespoke ladder (empty means they use the defaults).
  Future<List<CommissionTier>> listCommissionTiers({String? mowerId}) async {
    final res = await _client
        .rpc('admin_list_commission_tiers', params: {'p_mower_id': mowerId});
    return ((res as List?) ?? const [])
        .map((r) => CommissionTier.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// Upserts a tier. Pass [id] to update an existing one; omit for a new tier.
  /// [mowerId] scopes a NEW tier to one mower (null = a global default tier);
  /// on edit the row keeps its existing scope.
  Future<void> saveCommissionTier(CommissionTier tier,
          {String? id, String? mowerId}) =>
      _client.rpc('admin_save_commission_tier', params: {
        'p_name': tier.name,
        'p_min_jobs': tier.minJobs,
        'p_min_rating': tier.minRating,
        'p_min_reviews': tier.minReviews,
        'p_commission_pct': tier.commissionPct,
        'p_active': tier.active,
        'p_mower_id': mowerId,
        'p_id': id,
      });

  Future<void> deleteCommissionTier(String id) =>
      _client.rpc('admin_delete_commission_tier', params: {'p_id': id});

  /// The admin alerts inbox — support tickets, including chat off-app/cash
  /// flags and mower reliability flags. Open items sort first.
  Future<List<Map<String, dynamic>>> supportTickets() async {
    final res = await _client.rpc('admin_list_support_tickets');
    return ((res as List?) ?? const [])
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
  }

  Future<void> resolveTicket(String id, {String status = 'resolved'}) =>
      _client.rpc('admin_resolve_support_ticket',
          params: {'p_id': id, 'p_status': status});

  /// Count of open alerts, for the nav badge. Never throws (see [isAdmin]).
  Future<int> openTicketCount() async {
    if (_client.auth.currentUser == null) return 0;
    try {
      final res = await _client.rpc('admin_open_ticket_count');
      return (res as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Operations dashboard aggregates for a date range (inclusive).
  Future<Map<String, dynamic>> dashboard(DateTime from, DateTime to) async {
    String d(DateTime x) => '${x.year.toString().padLeft(4, '0')}-'
        '${x.month.toString().padLeft(2, '0')}-'
        '${x.day.toString().padLeft(2, '0')}';
    final res = await _client
        .rpc('admin_dashboard', params: {'p_from': d(from), 'p_to': d(to)});
    return Map<String, dynamic>.from(res as Map);
  }

  /// Whether the signed-in user is an admin. Used for routing only; the server
  /// enforces the same check on every call regardless of what this returns.
  ///
  /// Never throws. This runs on the sign-in path, and `is_admin()` does not
  /// exist until migration 0013 is applied — letting that error escape would
  /// break *mower* sign-in on any database that hasn't run it yet.
  Future<bool> isAdmin() async {
    if (_client.auth.currentUser == null) return false;
    try {
      final res = await _client.rpc('is_admin');
      return res == true;
    } catch (_) {
      return false;
    }
  }
}

final adminRepositoryProvider =
    Provider<AdminRepository>((ref) => AdminRepository());
