import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/ui.dart';
import '../data/mower_repository.dart';
import '../domain/commission_status.dart';
import '../domain/mower_account.dart';

/// Payouts & Stripe. Lets the mower set up their Stripe Connect (Express)
/// account, then open their Stripe dashboard to see balance / payout history.
///
/// Reached from the Earnings tab, the home payout summary, and the
/// setup/action-required banners. The day-to-day earnings breakdown lives on
/// [MowerEarningsScreen]; this screen is specifically the bank/Stripe side.
class MowerPayoutsScreen extends ConsumerStatefulWidget {
  const MowerPayoutsScreen({super.key});

  static const routePath = '/mower/payouts';

  @override
  ConsumerState<MowerPayoutsScreen> createState() =>
      _MowerPayoutsScreenState();
}

class _MowerPayoutsScreenState extends ConsumerState<MowerPayoutsScreen> {
  bool _loading = true;
  bool _busy = false;
  MowerAccount? _account;
  Map<String, dynamic>? _balance;
  CommissionStatus? _commission;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final repo = ref.read(mowerRepositoryProvider);
      // Sync live Stripe status first (updates onboarded + action-required),
      // best-effort so a Stripe hiccup still shows the stored values.
      try {
        await repo.refreshConnectStatus();
      } catch (_) {}
      final acct = await repo.mowerAccount();
      Map<String, dynamic>? balance;
      if (acct.connectOnboarded) {
        try {
          balance = await repo.connectBalance();
        } catch (_) {}
      }
      CommissionStatus? commission;
      try {
        commission = await repo.commissionStatus();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _account = acct;
        _balance = balance;
        _commission = commission;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load your payout details.';
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

  Future<void> _open(String url) async {
    final ok = await launchUrl(Uri.parse(url),
        mode: LaunchMode.externalApplication);
    if (!ok) _snack('Could not open the browser.');
  }

  Future<void> _startOnboarding() async {
    setState(() => _busy = true);
    try {
      final url = await ref.read(mowerRepositoryProvider).startConnectOnboarding();
      await _open(url);
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh() async {
    setState(() => _busy = true);
    try {
      await _load(); // _load syncs live status, then reloads the account
      final acct = _account;
      _snack(acct?.connectOnboarded == true
          ? (acct!.actionRequired
              ? 'Payouts on, but Stripe still needs something — see below.'
              : 'Payouts are set up — you’re good to go.')
          : 'Not finished yet — complete the Stripe steps and try again.');
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openDashboard() async {
    setState(() => _busy = true);
    try {
      final url = await ref.read(mowerRepositoryProvider).connectDashboardUrl();
      await _open(url);
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final acct = _account;
    return Scaffold(
      appBar: AppBar(title: const Text('Payouts')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : acct == null
              ? Center(child: Text(_error ?? 'Not available'))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  children: [
                    if (acct.actionRequired) ...[
                      _actionCard(acct),
                      const SizedBox(height: 16),
                    ],
                    acct.connectOnboarded
                        ? _activeCard(acct)
                        : _setupCard(),
                    if (acct.connectOnboarded && _balance?['exists'] == true) ...[
                      const SizedBox(height: 16),
                      _payoutsCard(_balance!),
                    ],
                    const SizedBox(height: 16),
                    _commissionCard(acct),
                    if (_commission != null) ...[
                      const SizedBox(height: 16),
                      _tierCard(_commission!),
                    ],
                    if (!acct.approved) ...[
                      const SizedBox(height: 16),
                      _pendingApprovalCard(),
                    ],
                  ],
                ),
    );
  }

  Widget _busyIcon(IconData fallback) => _busy
      ? const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
        )
      : Icon(fallback);

  Widget _setupCard() {
    final cs = Theme.of(context).colorScheme;
    return _Card(
      children: [
        Icon(Icons.account_balance_rounded, size: 36, color: cs.primary),
        const SizedBox(height: 12),
        const Text('Set up payouts',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        const SizedBox(height: 6),
        Text(
          'To get paid for jobs you need a Stripe payout account. You’ll add '
          'your bank details and verify your identity — this is part of '
          'becoming a MOWR. It only takes a few minutes.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _busy ? null : _startOnboarding,
            icon: _busyIcon(Icons.open_in_new_rounded),
            label: Text(_busy ? 'Please wait…' : 'Set up payout account'),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('I’ve finished — refresh status'),
          ),
        ),
      ],
    );
  }

  Widget _actionCard(MowerAccount acct) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.gpp_maybe_rounded, color: Colors.orange.shade800),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Action needed',
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            acct.requirement ??
                'Stripe needs a bit more information to finish verifying your '
                    'payouts.',
            style: TextStyle(color: AppColors.textPrimary),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: Colors.orange.shade800),
              onPressed: _busy ? null : _startOnboarding,
              icon: _busyIcon(Icons.open_in_new_rounded),
              label: Text(_busy ? 'Please wait…' : 'Complete verification'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _refresh,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('I’ve done it — refresh'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _activeCard(MowerAccount acct) {
    return _Card(
      children: [
        Icon(Icons.verified_rounded, size: 36, color: Colors.green.shade600),
        const SizedBox(height: 12),
        const Text('Payouts active',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        const SizedBox(height: 6),
        Text(
          'Your Stripe account is set up. Money from completed jobs is paid to '
          'your bank automatically. Open your Stripe dashboard to see your '
          'balance and full payout history.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _busy ? null : _openDashboard,
            icon: _busyIcon(Icons.open_in_new_rounded),
            label: Text(_busy ? 'Please wait…' : 'Open Stripe dashboard'),
          ),
        ),
      ],
    );
  }

  Widget _payoutsCard(Map<String, dynamic> b) {
    double money(dynamic pence) => ((pence as num?)?.toDouble() ?? 0) / 100;
    final available = money(b['available']);
    final pending = money(b['pending']);
    final next = b['nextPayout'] as Map?;
    final cs = Theme.of(context).colorScheme;

    String? nextLine;
    if (next != null) {
      final amt = money(next['amount']);
      final date = _fmtDate(next['arrivalDate']);
      nextLine = 'Next payout £${amt.toStringAsFixed(2)}'
          '${date != null ? ' — expected $date' : ''}';
    }

    return _Card(
      crossAxis: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.savings_rounded, size: 20, color: cs.primary),
            const SizedBox(width: 8),
            const Text('Expected payouts',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          ],
        ),
        const SizedBox(height: 12),
        _payoutRow('Available now', available, strong: true),
        const SizedBox(height: 6),
        _payoutRow('Still clearing', pending),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.primaryContainer.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.schedule_rounded, size: 18, color: cs.onSurface),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  nextLine ??
                      'No payout scheduled yet — one appears here once your '
                          'earnings have cleared.',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text('Stripe pays this to your bank automatically.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      ],
    );
  }

  Widget _payoutRow(String label, double amount, {bool strong = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: AppColors.textSecondary)),
        Text('£${amount.toStringAsFixed(2)}',
            style: TextStyle(
                fontWeight: strong ? FontWeight.w700 : FontWeight.w700,
                fontSize: strong ? 16 : 14)),
      ],
    );
  }

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

  Widget _commissionCard(MowerAccount acct) {
    final cs = Theme.of(context).colorScheme;
    return _Card(
      crossAxis: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.percent_rounded, size: 20, color: cs.primary),
            const SizedBox(width: 8),
            const Text('Your share',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'You keep ${acct.payoutPct.toStringAsFixed(0)}% of each job. '
          'MOWR’s fee is ${acct.commissionPct.toStringAsFixed(0)}%.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _tierCard(CommissionStatus c) {
    final cs = Theme.of(context).colorScheme;
    final next = c.nextTier;
    final rating = c.ratingAvg;
    return _Card(
      crossAxis: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.trending_up_rounded, size: 20, color: cs.primary),
            const SizedBox(width: 8),
            const Text('Lower your fee as you go',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          ],
        ),
        const SizedBox(height: 14),
        MiniStatRow(stats: [
          ('${c.jobsCompleted}', 'Jobs done'),
          (rating == null ? '—' : '${rating.toStringAsFixed(1)}★', 'Rating'),
          ('${c.reviewCount}', 'Reviews'),
        ]),
        const SizedBox(height: 12),
        if (c.currentTier != null)
          _pill('${c.currentTier} tier · ${c.commissionPct.toStringAsFixed(0)}% fee',
              cs.primary),
        if (next == null) ...[
          const SizedBox(height: 8),
          Text(
            c.currentTier == null
                ? 'Complete jobs and earn good reviews to start lowering your fee.'
                : "You're on the best tier — nicely done.",
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ] else ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Next: ${next.name} — ${next.commissionPct.toStringAsFixed(0)}% fee '
                  '(you keep ${(100 - next.commissionPct).toStringAsFixed(0)}%)',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
                const SizedBox(height: 10),
                _need('${next.minJobs} jobs completed', c.jobsCompleted,
                    next.minJobs, next.jobsNeeded == 0,
                    remaining: next.jobsNeeded == 0
                        ? null
                        : '${next.jobsNeeded} to go'),
                _need('${next.minRating.toStringAsFixed(1)}★ average rating',
                    null, null, next.ratingNeeded <= 0,
                    remaining: next.ratingNeeded <= 0
                        ? null
                        : '+${next.ratingNeeded.toStringAsFixed(1)}★'),
                _need('${next.minReviews} reviews', c.reviewCount,
                    next.minReviews, next.reviewsNeeded == 0,
                    remaining: next.reviewsNeeded == 0
                        ? null
                        : '${next.reviewsNeeded} more'),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _pill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text,
          style: TextStyle(
              color: color, fontWeight: FontWeight.w800, fontSize: 13)),
    );
  }

  Widget _need(String label, int? have, int? target, bool met,
      {String? remaining}) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(met ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
              size: 18,
              color: met ? cs.primary : const Color(0xFFB6B6B0)),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          if (!met && remaining != null)
            Text(remaining,
                style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _pendingApprovalCard() {
    return _Card(
      crossAxis: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.hourglass_top_rounded,
                size: 20, color: Colors.orange.shade800),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Awaiting approval',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Your account is being reviewed. Once approved (and payouts are set '
          'up) you’ll be able to accept jobs.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children, this.crossAxis = CrossAxisAlignment.center});
  final List<Widget> children;
  final CrossAxisAlignment crossAxis;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: crossAxis, children: children),
    );
  }
}
