import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../booking/domain/discount.dart';
import '../data/admin_repository.dart';

/// Discount modeller: admins create/edit loyalty rules like "recur and your 3rd
/// mow is 20% off". Rules feed the single PricingEngine.
class AdminDiscountsScreen extends ConsumerStatefulWidget {
  const AdminDiscountsScreen({super.key});

  static const routePath = '/admin/discounts';

  @override
  ConsumerState<AdminDiscountsScreen> createState() =>
      _AdminDiscountsScreenState();
}

class _AdminDiscountsScreenState extends ConsumerState<AdminDiscountsScreen> {
  bool _loading = true;
  String? _error;
  List<DiscountRule> _rules = const [];

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
      final rules = await ref.read(adminRepositoryProvider).listDiscounts();
      if (!mounted) return;
      setState(() {
        _rules = rules;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().contains('Admins only')
            ? 'This account is not an admin.'
            : 'Could not load discounts. Is migration 0016 applied?';
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

  Future<void> _edit({DiscountRule? existing}) async {
    final result = await showModalBottomSheet<DiscountRule>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _DiscountEditor(existing: existing),
      ),
    );
    if (result == null) return;
    try {
      await ref
          .read(adminRepositoryProvider)
          .saveDiscount(result, id: existing?.id);
      _snack('Saved.');
      await _load();
    } catch (e) {
      _snack('Could not save. $e');
    }
  }

  Future<void> _delete(DiscountRule rule) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete discount?'),
        content: Text('"${rule.name}" will stop applying to new quotes.'),
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
      await ref.read(adminRepositoryProvider).deleteDiscount(rule.id);
      _snack('Deleted.');
      await _load();
    } catch (e) {
      _snack('Could not delete. $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Discounts')),
      floatingActionButton: _loading || _error != null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _edit(),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New discount'),
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

    if (_rules.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(32, 96, 32, 32),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Icon(Icons.loyalty_outlined, size: 48, color: cs.primary),
          const SizedBox(height: 16),
          Text('No discounts yet',
              textAlign: TextAlign.center, style: text.titleMedium),
          const SizedBox(height: 4),
          Text('Tap “New discount” to reward recurring customers.',
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _rules.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final r = _rules[i];
        return Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            title: Text(r.name),
            subtitle: Text(r.summary),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!r.active)
                  Chip(
                    label: const Text('Off'),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: cs.surfaceContainerHighest,
                  ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () => _delete(r),
                ),
              ],
            ),
            onTap: () => _edit(existing: r),
          ),
        );
      },
    );
  }
}

class _DiscountEditor extends StatefulWidget {
  const _DiscountEditor({this.existing});
  final DiscountRule? existing;

  @override
  State<_DiscountEditor> createState() => _DiscountEditorState();
}

class _DiscountEditorState extends State<_DiscountEditor> {
  late final TextEditingController _name;
  late final TextEditingController _percent;
  late final TextEditingController _minOcc;
  late bool _recurringOnly;
  late bool _ongoing;
  late bool _active;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _percent =
        TextEditingController(text: e == null ? '' : _trim(e.percentOff));
    _minOcc = TextEditingController(text: '${e?.minOccurrence ?? 3}');
    _recurringOnly = e?.recurringOnly ?? true;
    _ongoing = e?.ongoing ?? false;
    _active = e?.active ?? true;
  }

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  @override
  void dispose() {
    _name.dispose();
    _percent.dispose();
    _minOcc.dispose();
    super.dispose();
  }

  void _save() {
    final pct = double.tryParse(_percent.text.trim());
    final occ = int.tryParse(_minOcc.text.trim());
    if (_name.text.trim().isEmpty || pct == null || pct <= 0 || pct > 100 ||
        occ == null || occ < 1) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Enter a name, a 1–100% amount, and occurrence ≥ 1.')));
      return;
    }
    Navigator.pop(
      context,
      DiscountRule(
        id: widget.existing?.id ?? '',
        name: _name.text.trim(),
        percentOff: pct,
        active: _active,
        recurringOnly: _recurringOnly,
        minOccurrence: occ,
        ongoing: _ongoing,
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
            Text(widget.existing == null ? 'New discount' : 'Edit discount',
                style: text.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _percent,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                    ],
                    decoration: const InputDecoration(
                        labelText: 'Amount off', suffixText: '%'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _minOcc,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'From mow #'),
                  ),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Every mow from then on'),
              subtitle: Text(_ongoing
                  ? 'Applies to that mow and all after it'
                  : 'Applies to that one mow only'),
              value: _ongoing,
              onChanged: (v) => setState(() => _ongoing = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Recurring bookings only'),
              value: _recurringOnly,
              onChanged: (v) => setState(() => _recurringOnly = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Active'),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: _save, child: const Text('Save discount')),
          ],
        ),
      ),
    );
  }
}
