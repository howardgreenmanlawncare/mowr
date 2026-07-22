import 'package:flutter/material.dart';

import '../domain/mower_account.dart';

/// The mower's home landing: at-a-glance earnings, available work, active job
/// and next payout. Fed by mower_dashboard() + connect-balance.
class MowerDashboard extends StatelessWidget {
  const MowerDashboard({
    super.key,
    required this.stats,
    required this.balance,
    required this.account,
    required this.onBrowseAvailable,
    required this.onOpenJob,
    required this.onOpenPayouts,
    required this.onRefresh,
  });

  final Map<String, dynamic> stats;
  final Map<String, dynamic>? balance;
  final MowerAccount account;
  final VoidCallback onBrowseAvailable;
  final void Function(String bookingId) onOpenJob;
  final VoidCallback onOpenPayouts;
  final Future<void> Function() onRefresh;

  double _d(dynamic v) => (v as num?)?.toDouble() ?? 0;
  int _i(dynamic v) => (v as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final todayEarnings = _d(stats['today_earnings']);
    final todayJobs = _i(stats['today_jobs']);
    final available = _i(stats['available_count']);
    final weekEarnings = _d(stats['week_earnings']);
    final active = stats['active'] as Map?;

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          Text('Today', style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          Row(
            children: [
              _StatTile(
                icon: Icons.payments_rounded,
                value: '£${todayEarnings.toStringAsFixed(2)}',
                label: 'Earned today',
                color: cs.primary,
              ),
              const SizedBox(width: 12),
              _StatTile(
                icon: Icons.grass_rounded,
                value: '$todayJobs',
                label: todayJobs == 1 ? 'Job done' : 'Jobs done',
                color: cs.primary,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _AvailableCard(count: available, onTap: onBrowseAvailable),
          if (active != null) ...[
            const SizedBox(height: 12),
            _ActiveJobCard(
              active: active,
              onResume: () => onOpenJob(active['booking_id'] as String),
            ),
          ],
          const SizedBox(height: 12),
          _PayoutSummary(
            balance: balance,
            onboarded: account.connectOnboarded,
            weekEarnings: weekEarnings,
            onOpenPayouts: onOpenPayouts,
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 10),
            Text(value,
                style: const TextStyle(
                    fontWeight: FontWeight.w900, fontSize: 22, height: 1)),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }
}

class _AvailableCard extends StatelessWidget {
  const _AvailableCard({required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.primaryContainer,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.work_outline_rounded, color: cs.onPrimaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      count == 0
                          ? 'No jobs available right now'
                          : '$count job${count == 1 ? '' : 's'} available now',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: cs.onPrimaryContainer),
                    ),
                    Text('Tap to browse and accept',
                        style: TextStyle(
                            fontSize: 12,
                            color: cs.onPrimaryContainer.withValues(alpha: 0.8))),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: cs.onPrimaryContainer),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActiveJobCard extends StatelessWidget {
  const _ActiveJobCard({required this.active, required this.onResume});
  final Map active;
  final VoidCallback onResume;

  String get _address => [active['line1'], active['city'], active['postcode']]
      .where((s) => (s as String?)?.trim().isNotEmpty ?? false)
      .join(', ');

  String get _statusLabel {
    switch (active['status'] as String? ?? '') {
      case 'accepted':
        return 'Accepted — head over when ready';
      case 'en_route':
        return 'On the way';
      case 'arrived':
        return 'Arrived';
      case 'in_progress':
        return 'In progress';
      default:
        return 'Active';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bolt_rounded, color: Colors.orange.shade800, size: 20),
              const SizedBox(width: 8),
              Text('Job in progress',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Colors.orange.shade900)),
            ],
          ),
          const SizedBox(height: 8),
          Text(_address,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 2),
          Text(_statusLabel,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onResume,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Resume job'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PayoutSummary extends StatelessWidget {
  const _PayoutSummary({
    required this.balance,
    required this.onboarded,
    required this.weekEarnings,
    required this.onOpenPayouts,
  });

  final Map<String, dynamic>? balance;
  final bool onboarded;
  final double weekEarnings;
  final VoidCallback onOpenPayouts;

  double _money(dynamic pence) => ((pence as num?)?.toDouble() ?? 0) / 100;

  String? _fmtDate(dynamic unixSeconds) {
    final s = (unixSeconds as num?)?.toInt();
    if (s == null) return null;
    final d = DateTime.fromMillisecondsSinceEpoch(s * 1000).toLocal();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final b = balance;
    final hasBalance = onboarded && b != null && b['exists'] == true;

    String payoutLine;
    if (!onboarded) {
      payoutLine = 'Set up payouts to start getting paid.';
    } else if (!hasBalance) {
      payoutLine = 'No payout scheduled yet.';
    } else {
      final next = b['nextPayout'] as Map?;
      if (next != null) {
        final amt = _money(next['amount']);
        final date = _fmtDate(next['arrivalDate']);
        payoutLine = 'Next payout £${amt.toStringAsFixed(2)}'
            '${date != null ? ' — expected $date' : ''}';
      } else {
        payoutLine = 'No payout scheduled yet.';
      }
    }

    final available = hasBalance ? _money(b['available']) : 0.0;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpenPayouts,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.savings_rounded, size: 20, color: cs.primary),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Payouts',
                        style: TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 15)),
                  ),
                  Icon(Icons.chevron_right_rounded, color: Colors.grey.shade500),
                ],
              ),
              const SizedBox(height: 10),
              _row('This week', '£${weekEarnings.toStringAsFixed(2)}'),
              if (hasBalance) ...[
                const SizedBox(height: 6),
                _row('Available now', '£${available.toStringAsFixed(2)}'),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.schedule_rounded,
                      size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(payoutLine,
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey.shade700)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: Colors.grey.shade700)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
      ],
    );
  }
}
