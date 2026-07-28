import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/admin_repository.dart';
import '../domain/commission_tier.dart';

/// Commission ladder editor: admins define performance tiers ("Silver — 30 jobs,
/// 4.3★, 15 reviews → 11% fee"). A mower gets the lowest tier they qualify for
/// (best-of vs any manual override). Feeds mower_commission() (migration 0020).
class AdminCommissionTiersScreen extends ConsumerStatefulWidget {
  const AdminCommissionTiersScreen({super.key, this.mowerId, this.mowerName});

  static const routePath = '/admin/commission-tiers';

  /// When set, edits this mower's OWN ladder (which replaces the global default
  /// ladder for them). Null edits the global defaults.
  final String? mowerId;
  final String? mowerName;

  bool get isPerMower => mowerId != null;

  @override
  ConsumerState<AdminCommissionTiersScreen> createState() =>
      _AdminCommissionTiersScreenState();
}

class _AdminCommissionTiersScreenState
    extends ConsumerState<AdminCommissionTiersScreen> {
  bool _loading = true;
  String? _error;
  List<CommissionTier> _tiers = const [];

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
      final tiers = await ref
          .read(adminRepositoryProvider)
          .listCommissionTiers(mowerId: widget.mowerId);
      if (!mounted) return;
      setState(() {
        _tiers = tiers;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().contains('Admins only')
            ? 'This account is not an admin.'
            : 'Could not load tiers. Is migration 0020 applied?';
      });
    }
  }

  void _snack(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(m)));
    }
  }

  Future<void> _edit({CommissionTier? existing}) async {
    final result = await showModalBottomSheet<CommissionTier>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _TierEditor(existing: existing),
      ),
    );
    if (result == null) return;
    try {
      await ref.read(adminRepositoryProvider).saveCommissionTier(
            result,
            id: existing?.id,
            mowerId: widget.mowerId,
          );
      _snack('Saved.');
      await _load();
    } catch (e) {
      _snack('Could not save. $e');
    }
  }

  Future<void> _delete(CommissionTier tier) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete tier?'),
        content: Text('"${tier.name}" will stop lowering anyone\'s commission.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(adminRepositoryProvider).deleteCommissionTier(tier.id);
      _snack('Deleted.');
      await _load();
    } catch (e) {
      _snack('Could not delete. $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isPerMower
            ? 'Tiers · ${widget.mowerName ?? 'Mower'}'
            : 'Commission tiers'),
      ),
      floatingActionButton: _loading || _error != null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _edit(),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New tier'),
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
        padding: const EdgeInsets.fromLTRB(24, 80, 24, 24),
        children: [
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 20),
          Center(
              child:
                  FilledButton(onPressed: _load, child: const Text('Retry'))),
        ],
      );
    }

    if (_tiers.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(32, 96, 32, 32),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Icon(Icons.trending_up_rounded, size: 48, color: cs.primary),
          const SizedBox(height: 16),
          Text(widget.isPerMower ? 'Using the default tiers' : 'No tiers yet',
              textAlign: TextAlign.center, style: text.titleMedium),
          const SizedBox(height: 4),
          Text(
              widget.isPerMower
                  ? 'This mower has no custom tiers, so the global defaults '
                      'apply. Add tiers here to give them a bespoke ladder.'
                  : 'Add tiers to reward mowers who complete jobs and earn good '
                      'reviews with a lower fee.',
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _tiers.length + (widget.isPerMower ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        if (widget.isPerMower && i == 0) {
          return Card(
            margin: EdgeInsets.zero,
            color: cs.primaryContainer.withValues(alpha: 0.4),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                'Custom ladder for this mower — it replaces the global defaults. '
                'Delete all tiers here to put them back on the defaults.',
                style: text.bodySmall,
              ),
            ),
          );
        }
        final t = _tiers[widget.isPerMower ? i - 1 : i];
        return Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            title: Text(t.name),
            subtitle: Text(t.summary),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!t.active)
                  Chip(
                    label: const Text('Off'),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: cs.surfaceContainerHighest,
                  ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () => _delete(t),
                ),
              ],
            ),
            onTap: () => _edit(existing: t),
          ),
        );
      },
    );
  }
}

class _TierEditor extends StatefulWidget {
  const _TierEditor({this.existing});
  final CommissionTier? existing;

  @override
  State<_TierEditor> createState() => _TierEditorState();
}

class _TierEditorState extends State<_TierEditor> {
  late final TextEditingController _name;
  late final TextEditingController _commission;
  late final TextEditingController _minJobs;
  late final TextEditingController _minRating;
  late final TextEditingController _minReviews;
  late bool _active;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _commission =
        TextEditingController(text: e == null ? '' : _trim(e.commissionPct));
    _minJobs = TextEditingController(text: '${e?.minJobs ?? 0}');
    _minRating =
        TextEditingController(text: e == null ? '4.0' : _trim(e.minRating));
    _minReviews = TextEditingController(text: '${e?.minReviews ?? 0}');
    _active = e?.active ?? true;
  }

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  @override
  void dispose() {
    _name.dispose();
    _commission.dispose();
    _minJobs.dispose();
    _minRating.dispose();
    _minReviews.dispose();
    super.dispose();
  }

  void _save() {
    final pct = double.tryParse(_commission.text.trim());
    final jobs = int.tryParse(_minJobs.text.trim());
    final rating = double.tryParse(_minRating.text.trim());
    final reviews = int.tryParse(_minReviews.text.trim());
    if (_name.text.trim().isEmpty ||
        pct == null || pct < 0 || pct > 100 ||
        jobs == null || jobs < 0 ||
        rating == null || rating < 0 || rating > 5 ||
        reviews == null || reviews < 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Enter a name, a 0–100% fee, and non-negative thresholds (rating ≤ 5).')));
      return;
    }
    Navigator.pop(
      context,
      CommissionTier(
        id: widget.existing?.id ?? '',
        name: _name.text.trim(),
        minJobs: jobs,
        minRating: rating,
        minReviews: reviews,
        commissionPct: pct,
        active: _active,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.existing == null ? 'New tier' : 'Edit tier',
                style: text.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration:
                  const InputDecoration(labelText: 'Name (e.g. Silver)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _commission,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
              ],
              decoration: const InputDecoration(
                  labelText: 'Commission at this tier', suffixText: '%'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _minJobs,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'Min jobs'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _minRating,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                    ],
                    decoration:
                        const InputDecoration(labelText: 'Min rating', suffixText: '★'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _minReviews,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'Min reviews'),
                  ),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Active'),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: _save, child: const Text('Save tier')),
          ],
        ),
      ),
    );
  }
}
