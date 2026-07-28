import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/ui.dart';
import '../data/admin_repository.dart';

/// Admin operations dashboard: everything happening for the chosen period, with
/// the same Today / 7 days / 30 days filters as the mower earnings view.
class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() =>
      _AdminDashboardScreenState();
}

enum _Range { today, week, month }

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen> {
  _Range _range = _Range.today;
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _data = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  (DateTime, DateTime) get _bounds {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return switch (_range) {
      _Range.today => (today, today),
      _Range.week => (today.subtract(const Duration(days: 6)), today),
      _Range.month => (today.subtract(const Duration(days: 29)), today),
    };
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final (from, to) = _bounds;
      final data = await ref.read(adminRepositoryProvider).dashboard(from, to);
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().contains('Admins only')
            ? 'This account is not an admin.'
            : 'Could not load the dashboard. Is migration 0015 applied?';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: SegmentedButton<_Range>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: _Range.today, label: Text('Today')),
                ButtonSegment(value: _Range.week, label: Text('7 days')),
                ButtonSegment(value: _Range.month, label: Text('30 days')),
              ],
              selected: {_range},
              onSelectionChanged: (s) {
                setState(() => _range = s.first);
                _load();
              },
            ),
          ),
        ),
      ),
      body: RefreshIndicator(onRefresh: _load, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(24, 80, 24, 24),
        children: [
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 20),
          Center(
            child: FilledButton(onPressed: _load, child: const Text('Retry')),
          ),
        ],
      );
    }

    final jobs = (_data['jobs'] as Map?) ?? const {};
    final revenue = (_data['revenue'] as Map?) ?? const {};
    final mowers = (_data['mowers'] as Map?) ?? const {};
    final attention = (_data['attention'] as Map?) ?? const {};
    final upcoming = (_data['upcoming'] as List?) ?? const [];

    int i(Map m, String k) => (m[k] as num?)?.toInt() ?? 0;
    double d(Map m, String k) => (m[k] as num?)?.toDouble() ?? 0;
    String money(double v) => '£${v.toStringAsFixed(2)}';

    final needsAttention =
        i(attention, 'revision_approvals') + i(attention, 'unassigned');

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (needsAttention > 0) ...[
          _AttentionCard(
            revisionApprovals: i(attention, 'revision_approvals'),
            unassigned: i(attention, 'unassigned'),
          ),
          const SizedBox(height: 16),
        ],

        StatHero(
          label: 'Gross revenue',
          value: money(d(revenue, 'gross')),
          secondary: [
            ('${i(revenue, 'jobs')}', 'Jobs done'),
            (money(d(revenue, 'commission')), 'Commission'),
            (money(d(revenue, 'mower_payout')), 'Payouts'),
          ],
        ),
        const Hairline(),
        _section('Jobs'),
        _TileRow(tiles: [
          _Tile(label: 'Total', value: '${i(jobs, 'total')}'),
          _Tile(label: 'Completed', value: '${i(jobs, 'completed')}'),
          _Tile(label: 'In progress', value: '${i(jobs, 'in_progress')}'),
        ]),
        const SizedBox(height: 10),
        _TileRow(tiles: [
          _Tile(label: 'Scheduled', value: '${i(jobs, 'scheduled')}'),
          _Tile(
            label: 'Awaiting mower',
            value: '${i(jobs, 'awaiting_mower')}',
            warn: i(jobs, 'awaiting_mower') > 0,
          ),
          _Tile(label: 'Cancelled', value: '${i(jobs, 'cancelled')}'),
        ]),

        const SizedBox(height: 20),
        _section('Mowers'),
        _TileRow(tiles: [
          _Tile(label: 'Active', value: '${i(mowers, 'active')}'),
          _Tile(label: 'Approved', value: '${i(mowers, 'approved')}'),
          _Tile(
            label: 'Awaiting approval',
            value: '${i(mowers, 'awaiting_approval')}',
            warn: i(mowers, 'awaiting_approval') > 0,
          ),
        ]),

        const SizedBox(height: 20),
        _section('Next 7 days'),
        _UpcomingStrip(upcoming: upcoming),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      );
}

class _TileRow extends StatelessWidget {
  const _TileRow({required this.tiles});
  final List<_Tile> tiles;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(child: tiles[i]),
          ],
        ],
      );
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value, this.warn = false});

  final String label;
  final String value;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: warn ? cs.errorContainer : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: text.titleLarge?.copyWith(
                  color: warn ? cs.onErrorContainer : null,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label,
              style: text.labelSmall?.copyWith(
                  color:
                      warn ? cs.onErrorContainer : cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _AttentionCard extends StatelessWidget {
  const _AttentionCard({
    required this.revisionApprovals,
    required this.unassigned,
  });

  final int revisionApprovals;
  final int unassigned;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final parts = <String>[
      if (unassigned > 0)
        '$unassigned job${unassigned == 1 ? '' : 's'} with no mower',
      if (revisionApprovals > 0)
        '$revisionApprovals re-measure${revisionApprovals == 1 ? '' : 's'} awaiting customer',
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.priority_high_rounded, color: cs.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Needs attention',
                    style: text.titleSmall
                        ?.copyWith(color: cs.onErrorContainer)),
                const SizedBox(height: 2),
                Text(parts.join(' · '),
                    style: text.bodySmall
                        ?.copyWith(color: cs.onErrorContainer)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UpcomingStrip extends StatelessWidget {
  const _UpcomingStrip({required this.upcoming});
  final List upcoming;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    if (upcoming.isEmpty) {
      return Text('No jobs booked in the next 7 days.',
          style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant));
    }

    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return SizedBox(
      height: 82,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final u in upcoming)
            Builder(builder: (context) {
              final map = u as Map;
              final date = DateTime.tryParse(map['date'] as String? ?? '');
              final count = (map['count'] as num?)?.toInt() ?? 0;
              return Container(
                width: 64,
                margin: const EdgeInsets.only(right: 10),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('$count', style: text.titleLarge),
                    Text(
                      date == null ? '' : days[date.weekday - 1],
                      style: text.labelSmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}
