import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/admin_repository.dart';
import '../domain/admin_models.dart';
import 'admin_commission_tiers_screen.dart';
import 'admin_settings_screen.dart';

/// The mower vetting queue — the thing that previously required opening the
/// Supabase dashboard and editing `profiles.mower_approved` by hand.
///
/// Mowers awaiting approval sort to the top, because until an admin acts they
/// cannot earn and the job pool stays thin.
class AdminMowersScreen extends ConsumerStatefulWidget {
  const AdminMowersScreen({super.key});

  static const routePath = '/admin';

  @override
  ConsumerState<AdminMowersScreen> createState() => _AdminMowersScreenState();
}

class _AdminMowersScreenState extends ConsumerState<AdminMowersScreen> {
  bool _loading = true;
  String? _error;
  List<AdminMower> _mowers = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final mowers = await ref.read(adminRepositoryProvider).listMowers();
      if (!mounted) return;
      setState(() {
        _mowers = mowers;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _friendly(e);
      });
    }
  }

  /// The RPCs raise 'Admins only' — surface that plainly rather than as a raw
  /// Postgres error, since it's the most likely failure on a fresh install.
  String _friendly(Object e) {
    final m = e.toString();
    if (m.contains('Admins only')) {
      return 'This account is not an admin. Set role = \'admin\' on your '
          'profile row, then sign in again.';
    }
    if (m.contains('admin_list_mowers') || m.contains('does not exist')) {
      return 'Admin functions are missing — apply migration 0013_admin.sql.';
    }
    return 'Could not load mowers.';
  }

  void _snack(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(m)));
    }
  }

  Future<void> _toggleApproval(AdminMower mower) async {
    final approving = !mower.approved;
    if (!approving) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Remove approval?'),
          content: Text(
            '${mower.displayName} will stop seeing available jobs. Jobs they '
            'have already accepted are unaffected.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Remove'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }

    try {
      await ref
          .read(adminRepositoryProvider)
          .setApproved(mower.id, approved: approving);
      _snack(approving
          ? '${mower.displayName} approved.'
          : 'Approval removed from ${mower.displayName}.');
      await _load();
    } catch (e) {
      _snack(_friendly(e));
    }
  }

  Future<void> _editCommission(AdminMower mower) async {
    final controller = TextEditingController(
      text: mower.commissionPct?.toStringAsFixed(1) ?? '',
    );
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Commission — ${mower.displayName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Percentage MOWR keeps from each job. Leave blank to use the '
              'global default.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Commission %',
                suffixText: '%',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (value == null) return;

    final pct = value.isEmpty ? null : double.tryParse(value);
    if (value.isNotEmpty && (pct == null || pct < 0 || pct > 100)) {
      _snack('Enter a percentage between 0 and 100, or leave it blank.');
      return;
    }

    try {
      await ref.read(adminRepositoryProvider).setCommission(mower.id, pct);
      _snack(pct == null
          ? 'Using the default commission.'
          : 'Commission set to ${pct.toStringAsFixed(1)}%.');
      await _load();
    } catch (e) {
      _snack(_friendly(e));
    }
  }

  void _editTiers(AdminMower mower) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AdminCommissionTiersScreen(
        mowerId: mower.id,
        mowerName: mower.displayName,
      ),
    ));
  }

  List<AdminMower> get _ordered {
    final waiting = _mowers.where((m) => !m.approved).toList();
    final rest = _mowers.where((m) => m.approved).toList();
    return [...waiting, ...rest];
  }

  @override
  Widget build(BuildContext context) {
    final waiting = _mowers.where((m) => !m.approved).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mowers'),
        actions: [
          IconButton(
            tooltip: 'Pricing & settings',
            icon: const Icon(Icons.tune_rounded),
            onPressed: () => context.push(AdminSettingsScreen.routePath),
          ),
        ],
        bottom: waiting == 0
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(28),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '$waiting waiting for approval',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
      ),
      body: RefreshIndicator(onRefresh: _load, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(32, 80, 32, 32),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Icon(Icons.lock_outline_rounded, size: 48, color: cs.error),
          const SizedBox(height: 16),
          Text(_error!, textAlign: TextAlign.center, style: text.bodyLarge),
          const SizedBox(height: 24),
          Center(
            child: FilledButton(
                onPressed: _load, child: const Text('Try again')),
          ),
        ],
      );
    }

    if (_mowers.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(32, 96, 32, 32),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Icon(Icons.people_outline_rounded, size: 48, color: cs.primary),
          const SizedBox(height: 16),
          Text('No mowers have applied yet.',
              textAlign: TextAlign.center, style: text.titleMedium),
        ],
      );
    }

    final items = _ordered;
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) => _MowerCard(
        mower: items[i],
        onToggleApproval: () => _toggleApproval(items[i]),
        onEditCommission: () => _editCommission(items[i]),
        onEditTiers: () => _editTiers(items[i]),
      ),
    );
  }
}

class _MowerCard extends StatelessWidget {
  const _MowerCard({
    required this.mower,
    required this.onToggleApproval,
    required this.onEditCommission,
    required this.onEditTiers,
  });

  final AdminMower mower;
  final VoidCallback onToggleApproval;
  final VoidCallback onEditCommission;
  final VoidCallback onEditTiers;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final blocked = mower.blockedReason;

    return Card(
      margin: EdgeInsets.zero,
      color: mower.approved ? null : cs.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(mower.displayName, style: text.titleMedium),
                ),
                if (mower.canWork)
                  Chip(
                    label: const Text('Active'),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: cs.primaryContainer,
                  ),
              ],
            ),
            if (mower.email != null) ...[
              const SizedBox(height: 2),
              Text(mower.email!,
                  style:
                      text.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                _Fact(
                  label: 'Jobs done',
                  value: '${mower.jobsCompleted}',
                ),
                _Fact(
                  label: 'Commission',
                  value: mower.commissionPct == null
                      ? 'Default'
                      : '${mower.commissionPct!.toStringAsFixed(1)}%',
                ),
                _Fact(
                  label: 'Mobile',
                  value: mower.phoneVerified ? 'Verified' : 'Unverified',
                ),
                _Fact(
                  label: 'Payouts',
                  value: mower.connectOnboarded ? 'Set up' : 'Not set up',
                ),
                _Fact(
                  label: 'Auto-accept',
                  value: mower.autoAllocate ? 'On' : 'Off',
                ),
              ],
            ),
            if (mower.refusals30d > 0) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    mower.refusalFlag
                        ? Icons.warning_amber_rounded
                        : Icons.report_gmailerrorred_rounded,
                    size: 18,
                    color: mower.refusalFlag ? cs.error : cs.tertiary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      mower.refusalFlag
                          ? 'Dropped ${mower.refusals30d} jobs (refused/cancelled) in 30 days — reliability flag; auto-accept paused.'
                          : 'Dropped ${mower.refusals30d} job${mower.refusals30d == 1 ? '' : 's'} (refused/cancelled) in 30 days.',
                      style: text.bodySmall?.copyWith(
                        color: mower.refusalFlag ? cs.error : cs.tertiary,
                        fontWeight:
                            mower.refusalFlag ? FontWeight.w600 : null,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (blocked != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 18, color: cs.onErrorContainer),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      blocked,
                      style: text.bodySmall
                          ?.copyWith(color: cs.onErrorContainer),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onEditCommission,
                    child: const Text('Commission'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: onEditTiers,
                    child: const Text('Tiers'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onToggleApproval,
                child: Text(mower.approved ? 'Unapprove' : 'Approve'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: text.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
        Text(value, style: text.bodyMedium),
      ],
    );
  }
}
