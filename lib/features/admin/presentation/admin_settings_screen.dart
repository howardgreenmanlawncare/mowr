import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../booking/providers/pricing_provider.dart';
import '../data/admin_repository.dart';
import '../domain/admin_models.dart';
import 'admin_commission_tiers_screen.dart';
import 'admin_discounts_screen.dart';

/// Pricing rates, re-measure threshold and default commission — the settings
/// that previously required hand-editing the `pricing_rules` row.
///
/// Saving here updates the live pricing the app quotes with (see
/// `pricingRulesProvider`), so these are the real numbers, not a display copy.
class AdminSettingsScreen extends ConsumerStatefulWidget {
  const AdminSettingsScreen({super.key});

  static const routePath = '/admin/settings';

  @override
  ConsumerState<AdminSettingsScreen> createState() =>
      _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends ConsumerState<AdminSettingsScreen> {
  final _controllers = <String, TextEditingController>{};
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _ctrl(String key, double value) =>
      _controllers.putIfAbsent(
        key,
        () => TextEditingController(text: _trim(value)),
      );

  /// 0.15 not 0.1500, 12 not 12.00 — these are rates a human types.
  static String _trim(double v) {
    var s = v.toStringAsFixed(4);
    if (s.contains('.')) {
      s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
    }
    return s;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = await ref.read(adminRepositoryProvider).settings();
      if (!mounted) return;
      _seed(s);
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().contains('Admins only')
            ? 'This account is not an admin.'
            : 'Could not load settings. Is migration 0013 applied?';
      });
    }
  }

  void _seed(AdminSettings s) {
    void set(String k, double v) => _ctrl(k, v).text = _trim(v);
    set('mow_turn_up', s.mowTurnUp);
    set('mow_rate_per_sqm', s.mowRatePerSqm);
    set('mow_minimum', s.mowMinimum);
    set('edge_turn_up', s.edgeTurnUp);
    set('edge_rate_per_metre', s.edgeRatePerMetre);
    set('edge_minimum', s.edgeMinimum);
    set('height_mult_low', s.heightMultLow);
    set('height_mult_medium', s.heightMultMedium);
    set('height_mult_high', s.heightMultHigh);
    set('revise_auto_threshold_pct', s.reviseAutoThresholdPct);
    set('default_commission_pct', s.defaultCommissionPct);
  }

  double? _read(String key) =>
      double.tryParse(_controllers[key]?.text.trim() ?? '');

  Future<void> _save() async {
    final values = <String, double>{};
    for (final key in _controllers.keys) {
      final v = _read(key);
      if (v == null || v < 0) {
        _snack('Every field needs a number (0 or more).');
        return;
      }
      values[key] = v;
    }

    setState(() => _saving = true);
    try {
      final next = AdminSettings(
        mowTurnUp: values['mow_turn_up']!,
        mowRatePerSqm: values['mow_rate_per_sqm']!,
        mowMinimum: values['mow_minimum']!,
        edgeTurnUp: values['edge_turn_up']!,
        edgeRatePerMetre: values['edge_rate_per_metre']!,
        edgeMinimum: values['edge_minimum']!,
        heightMultLow: values['height_mult_low']!,
        heightMultMedium: values['height_mult_medium']!,
        heightMultHigh: values['height_mult_high']!,
        reviseAutoThresholdPct: values['revise_auto_threshold_pct']!,
        defaultCommissionPct: values['default_commission_pct']!,
      );
      final saved =
          await ref.read(adminRepositoryProvider).updateSettings(next);
      if (!mounted) return;
      _seed(saved);
      // Push the new rates into the live pricing engine so quotes taken from
      // here on use them without an app restart.
      ref.read(pricingRulesProvider.notifier).state = saved.toPricingRules();
      _snack('Saved. New quotes will use these rates.');
    } catch (e) {
      _snack(e.toString().contains('Admins only')
          ? 'This account is not an admin.'
          : 'Could not save.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(m)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pricing & settings')),
      bottomNavigationBar: _loading || _error != null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Saving…' : 'Save changes'),
                ),
              ),
            ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(32, 80, 32, 32),
        child: Column(
          children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton(onPressed: _load, child: const Text('Try again')),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const _SectionHeader(
          title: 'Mowing',
          subtitle: 'Charged once per visit, plus a rate for every square '
              'metre of lawn.',
        ),
        _Field(controller: _ctrl('mow_turn_up', 0), label: 'Turn-up fee', prefix: '£'),
        _Field(
            controller: _ctrl('mow_rate_per_sqm', 0),
            label: 'Rate per m²',
            prefix: '£'),
        _Field(
            controller: _ctrl('mow_minimum', 0),
            label: 'Minimum charge',
            prefix: '£'),
        const SizedBox(height: 24),
        const _SectionHeader(
          title: 'Edging',
          subtitle: 'Only charged on lawns the customer asks to have edged.',
        ),
        _Field(
            controller: _ctrl('edge_turn_up', 0),
            label: 'Turn-up fee',
            prefix: '£'),
        _Field(
            controller: _ctrl('edge_rate_per_metre', 0),
            label: 'Rate per metre',
            prefix: '£'),
        _Field(
            controller: _ctrl('edge_minimum', 0),
            label: 'Minimum charge',
            prefix: '£'),
        const SizedBox(height: 24),
        const _SectionHeader(
          title: 'Grass length multipliers',
          subtitle: 'Longer grass takes longer. The mowing price is multiplied '
              'by these.',
        ),
        _Field(controller: _ctrl('height_mult_low', 0), label: 'Short grass'),
        _Field(
            controller: _ctrl('height_mult_medium', 0), label: 'Medium grass'),
        _Field(controller: _ctrl('height_mult_high', 0), label: 'Long grass'),
        const SizedBox(height: 24),
        const _SectionHeader(
          title: 'Operations',
          subtitle: 'How much a mower may re-price on site before the customer '
              'has to approve, and what MOWR keeps by default.',
        ),
        _Field(
            controller: _ctrl('revise_auto_threshold_pct', 0),
            label: 'Auto-approve re-measure within',
            suffix: '%'),
        _Field(
            controller: _ctrl('default_commission_pct', 0),
            label: 'Default commission',
            suffix: '%'),
        const SizedBox(height: 24),
        const _SectionHeader(
          title: 'Discounts',
          subtitle: 'Loyalty rules that reward recurring customers, e.g. '
              '"3rd mow 20% off".',
        ),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const AdminDiscountsScreen())),
          icon: const Icon(Icons.loyalty_rounded),
          label: const Text('Manage discounts'),
        ),
        const SizedBox(height: 24),
        const _SectionHeader(
          title: 'Mower commission tiers',
          subtitle: 'Reward mowers who complete jobs and earn good reviews with '
              'a lower fee, e.g. "Silver — 30 jobs, 4.3★ → 11%".',
        ),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const AdminCommissionTiersScreen())),
          icon: const Icon(Icons.trending_up_rounded),
          label: const Text('Manage commission tiers'),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: text.titleMedium),
          const SizedBox(height: 2),
          Text(subtitle,
              style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    this.prefix,
    this.suffix,
  });

  final TextEditingController controller;
  final String label;
  final String? prefix;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          prefixText: prefix,
          suffixText: suffix,
        ),
      ),
    );
  }
}
