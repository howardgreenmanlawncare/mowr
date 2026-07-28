import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/ui.dart';
import '../data/mower_repository.dart';
import '../domain/mower_earnings.dart';
import 'mower_payouts_screen.dart';

/// Earnings breakdown for the signed-in mower. A filter chip picks a date
/// range (Today / 7 days / 30 days / Year to date / Custom); the screen calls
/// the `mower_earnings` RPC for that range and shows totals + a per-job list,
/// with a CSV export of the filtered rows via the system share sheet.
///
/// Used both as the "Earnings" bottom-nav tab (with [onOpenPayouts] wired to
/// switch to the payouts route) and as a standalone route.
class MowerEarningsScreen extends ConsumerStatefulWidget {
  const MowerEarningsScreen({super.key, this.onOpenPayouts});

  /// Opens the Stripe payouts / bank screen. If null, the screen pushes the
  /// [MowerPayoutsScreen] route itself.
  final VoidCallback? onOpenPayouts;

  static const routePath = '/mower/earnings';

  @override
  ConsumerState<MowerEarningsScreen> createState() =>
      _MowerEarningsScreenState();
}

enum _Range { today, week, month, ytd, custom }

extension on _Range {
  String get label => switch (this) {
        _Range.today => 'Today',
        _Range.week => '7 days',
        _Range.month => '30 days',
        _Range.ytd => 'Year to date',
        _Range.custom => 'Custom',
      };
}

class _MowerEarningsScreenState extends ConsumerState<MowerEarningsScreen> {
  _Range _range = _Range.month;
  late DateTime _from;
  late DateTime _to;
  bool _loading = true;
  bool _exporting = false;
  String? _error;
  MowerEarnings? _data;

  @override
  void initState() {
    super.initState();
    // Default range: last 30 days. Set the dates directly (no setState during
    // init), then kick off the first load.
    final today = DateUtils.dateOnly(DateTime.now());
    _from = _minusDays(today, 29);
    _to = today;
    _load();
  }

  DateTime _minusDays(DateTime d, int n) => DateTime(d.year, d.month, d.day - n);

  void _applyRange(_Range range, {DateTimeRange? custom, bool load = true}) {
    final today = DateUtils.dateOnly(DateTime.now());
    late DateTime f;
    late DateTime t;
    switch (range) {
      case _Range.today:
        f = today;
        t = today;
      case _Range.week:
        f = _minusDays(today, 6);
        t = today;
      case _Range.month:
        f = _minusDays(today, 29);
        t = today;
      case _Range.ytd:
        f = DateTime(today.year, 1, 1);
        t = today;
      case _Range.custom:
        f = DateUtils.dateOnly(custom!.start);
        t = DateUtils.dateOnly(custom.end);
    }
    setState(() {
      _range = range;
      _from = f;
      _to = t;
    });
    if (load) _load();
  }

  Future<void> _pickCustom() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final initial = _range == _Range.custom
        ? DateTimeRange(start: _from, end: _to)
        : DateTimeRange(start: _minusDays(today, 29), end: today);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020, 1, 1),
      lastDate: today,
      initialDateRange: initial,
      helpText: 'Earnings period',
      saveText: 'Done',
    );
    if (picked != null) _applyRange(_Range.custom, custom: picked);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ref.read(mowerRepositoryProvider).earnings(_from, _to);
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load your earnings. Pull down to try again.';
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

  void _openPayouts() {
    final cb = widget.onOpenPayouts;
    if (cb != null) {
      cb();
    } else {
      context.push(MowerPayoutsScreen.routePath);
    }
  }

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  String _pretty(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  String _rangeLabel() =>
      _from == _to ? _pretty(_from) : '${_pretty(_from)} – ${_pretty(_to)}';

  /// RFC-4180-ish escaping: wrap in quotes if the value contains a comma,
  /// quote, or newline, doubling any embedded quotes.
  String _csvCell(String s) {
    if (s.contains(',') || s.contains('"') || s.contains('\n') ||
        s.contains('\r')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  String _buildCsv(MowerEarnings d) {
    final lines = <String>['Date,Address,Postcode,Job total,Fee,Net'];
    for (final r in d.rows) {
      lines.add([
        r.date,
        r.address,
        r.postcode ?? '',
        r.jobTotal.toStringAsFixed(2),
        r.fee.toStringAsFixed(2),
        r.net.toStringAsFixed(2),
      ].map(_csvCell).join(','));
    }
    lines.add([
      'Totals',
      '',
      '',
      d.gross.toStringAsFixed(2),
      d.fees.toStringAsFixed(2),
      d.net.toStringAsFixed(2),
    ].map(_csvCell).join(','));
    return lines.join('\r\n');
  }

  Future<void> _exportCsv() async {
    final d = _data;
    if (d == null || d.rows.isEmpty) {
      _snack('Nothing to export for this period.');
      return;
    }
    setState(() => _exporting = true);
    try {
      final csv = _buildCsv(d);
      final name = 'mowr-earnings_${_iso(_from)}_to_${_iso(_to)}.csv';
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$name');
      await file.writeAsString(csv, flush: true);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'text/csv', name: name)],
        subject: 'MOWR earnings — ${_rangeLabel()}',
        text: 'MOWR earnings — ${_rangeLabel()}',
      ));
    } catch (e) {
      _snack('Could not export CSV: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Earnings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_balance_wallet_rounded),
            tooltip: 'Payouts & bank',
            onPressed: _openPayouts,
          ),
        ],
      ),
      body: Column(
        children: [
          _chipsBar(),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _chipsBar() {
    Widget chip(_Range r) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text(r.label),
            selected: _range == r,
            onSelected: (_) {
              if (r == _Range.custom) {
                _pickCustom();
              } else {
                _applyRange(r);
              }
            },
          ),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: _Range.values.map(chip).toList()),
      ),
    );
  }

  Widget _body() {
    if (_data == null) {
      if (_loading) return const Center(child: CircularProgressIndicator());
      return _errorView();
    }
    final d = _data!;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          StatHero(
            label: 'Net · ${_range.label}',
            value: '£${d.net.toStringAsFixed(2)}',
            secondary: [
              ('${d.jobs}', 'Jobs'),
              ('£${d.gross.toStringAsFixed(2)}', 'Charged'),
              ('£${d.fees.toStringAsFixed(2)}', 'MOWR fee'),
            ],
          ),
          const SizedBox(height: 6),
          Text(_rangeLabel(), style: Theme.of(context).textTheme.bodySmall),
          const Hairline(),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed:
                  _exporting || d.rows.isEmpty ? null : _exportCsv,
              icon: _exporting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.ios_share_rounded),
              label: Text(_exporting ? 'Preparing…' : 'Export CSV'),
            ),
          ),
          const SizedBox(height: 16),
          if (d.rows.isEmpty)
            _emptyRows()
          else ...[
            Eyebrow(d.jobs == 1 ? '1 job' : '${d.jobs} jobs'),
            const SizedBox(height: 2),
            for (var i = 0; i < d.rows.length; i++)
              _row(d.rows[i], topBorder: i > 0),
          ],
        ],
      ),
    );
  }

  Widget _errorView() {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        children: [
          const SizedBox(height: 80),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _error ?? 'Could not load your earnings.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyRows() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 40, 8, 8),
      child: Center(
        child: Column(
          children: [
            const Icon(Icons.grass_rounded, size: 40,
                color: AppColors.textSecondary),
            const SizedBox(height: 12),
            Text('No completed jobs in this period.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _row(EarningsRow r, {bool topBorder = false}) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: topBorder
          ? const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.border)))
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.address.isEmpty ? 'Property' : r.address,
                    style: text.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  '${r.dateLabel}'
                  '${(r.postcode ?? '').trim().isNotEmpty ? ' · ${r.postcode}' : ''}',
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('£${r.net.toStringAsFixed(2)}',
                  style: text.titleSmall?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()])),
              const SizedBox(height: 2),
              Text(
                '£${r.jobTotal.toStringAsFixed(2)} · fee £${r.fee.toStringAsFixed(2)}',
                style: text.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
