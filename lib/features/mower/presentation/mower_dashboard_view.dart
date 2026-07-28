import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/ui.dart';
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
    final todayEarnings = _d(stats['today_earnings']);
    final todayJobs = _i(stats['today_jobs']);
    final available = _i(stats['available_count']);
    final weekEarnings = _d(stats['week_earnings']);
    final active = stats['active'] as Map?;

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        children: [
          StatHero(
            label: 'Earned today',
            value: '£${todayEarnings.toStringAsFixed(2)}',
            secondary: [
              ('$todayJobs', 'Jobs today'),
              ('£${weekEarnings.toStringAsFixed(0)}', 'This week'),
            ],
          ),
          const Hairline(),
          _AvailableRow(count: available, onTap: onBrowseAvailable),
          if (active != null) ...[
            const Hairline(),
            const Eyebrow('Active job'),
            const SizedBox(height: 10),
            _ActiveJobCard(
              active: active,
              onResume: () => onOpenJob(active['booking_id'] as String),
            ),
          ],
          const Hairline(),
          _PayoutSummary(
            balance: balance,
            onboarded: account.connectOnboarded,
            onOpenPayouts: onOpenPayouts,
          ),
        ],
      ),
    );
  }
}

class _AvailableRow extends StatelessWidget {
  const _AvailableRow({required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    count == 0
                        ? 'No jobs available right now'
                        : '$count job${count == 1 ? '' : 's'} available now',
                    style: text.titleMedium,
                  ),
                  const SizedBox(height: 2),
                  Text('Browse and accept', style: text.bodySmall),
                ],
              ),
            ),
            if (count > 0) const StatusPill('Now', tone: PillTone.soft),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward,
                size: 18, color: AppColors.textSecondary),
          ],
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

  ({String label, PillTone tone}) get _status {
    switch (active['status'] as String? ?? '') {
      case 'accepted':
        return (label: 'Accepted', tone: PillTone.neutral);
      case 'en_route':
        return (label: 'On the way', tone: PillTone.live);
      case 'arrived':
        return (label: 'Arrived', tone: PillTone.live);
      case 'in_progress':
        return (label: 'In progress', tone: PillTone.live);
      default:
        return (label: 'Active', tone: PillTone.neutral);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final status = _status;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StatusPill(status.label,
                tone: status.tone, dot: status.tone == PillTone.live),
            const SizedBox(height: 12),
            Text(_address, style: text.titleMedium),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onResume,
                child: const Text('Resume job'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PayoutSummary extends StatelessWidget {
  const _PayoutSummary({
    required this.balance,
    required this.onboarded,
    required this.onOpenPayouts,
  });

  final Map<String, dynamic>? balance;
  final bool onboarded;
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
    final text = Theme.of(context).textTheme;
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

    return InkWell(
      onTap: onOpenPayouts,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: Eyebrow('Payouts')),
              const Icon(Icons.arrow_forward,
                  size: 16, color: AppColors.textSecondary),
            ],
          ),
          const SizedBox(height: 4),
          if (hasBalance)
            DataRow2(
                label: 'Available now',
                value: '£${available.toStringAsFixed(2)}'),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.schedule_rounded,
                  size: 15, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Expanded(child: Text(payoutLine, style: text.bodySmall)),
            ],
          ),
        ],
      ),
    );
  }
}
