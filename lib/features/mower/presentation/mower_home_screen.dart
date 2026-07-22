import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/data/auth_repository.dart';
import '../data/mower_repository.dart';
import '../domain/mower_account.dart';
import '../domain/mower_job.dart';
import 'mower_dashboard_view.dart';
import 'mower_earnings_screen.dart';
import 'mower_payouts_screen.dart';

class MowerHomeScreen extends ConsumerStatefulWidget {
  const MowerHomeScreen({super.key});

  static const routePath = '/mower/home';

  @override
  ConsumerState<MowerHomeScreen> createState() => _MowerHomeScreenState();
}

class _MowerHomeScreenState extends ConsumerState<MowerHomeScreen> {
  /// Bottom-nav index: 0 = Home, 1 = Jobs, 2 = Earnings.
  int _index = 0;

  /// Segment inside the Jobs tab: 0 = Available, 1 = Mine, 2 = History.
  int _jobsSegment = 0;

  bool _loading = true;
  MowerAccount? _account;
  Map<String, dynamic> _dashboard = const {};
  Map<String, dynamic>? _balance;
  List<MowerJob> _available = const [];
  List<MowerJob> _mine = const [];
  List<MowerJob> _history = const [];
  String? _error;

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
      final repo = ref.read(mowerRepositoryProvider);
      // Best-effort live Stripe sync so an "action required" shows up promptly.
      try {
        await repo.refreshConnectStatus();
      } catch (_) {}
      final account = await repo.mowerAccount();
      final dashboard = await repo.dashboard();
      final available = await repo.availableJobs();
      final mine = await repo.myJobs();
      final history = await repo.jobHistory();
      Map<String, dynamic>? balance;
      if (account.connectOnboarded) {
        try {
          balance = await repo.connectBalance();
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _account = account;
        _dashboard = dashboard;
        _balance = balance;
        _available = available;
        _mine = mine;
        _history = history;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load jobs. Pull down to try again.';
      });
    }
  }

  Future<void> _accept(MowerJob job) async {
    try {
      final won = await ref.read(mowerRepositoryProvider).acceptJob(job.bookingId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(won
            ? 'Job accepted — it’s yours.'
            : 'Another mower got there first.'),
      ));
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Couldn’t accept that job.')),
      );
    }
  }

  void _openPayouts() {
    context.push(MowerPayoutsScreen.routePath).then((_) => _load());
  }

  void _openJob(String id) {
    context.push('/mower/job/$id').then((_) => _load());
  }

  void _browseAvailable() {
    setState(() {
      _index = 1;
      _jobsSegment = 0;
    });
  }

  Future<void> _signOut() async {
    await ref.read(authRepositoryProvider).signOut();
    if (mounted) context.go('/');
  }

  /// The gating banner (payout setup / action needed / awaiting approval).
  /// Built fresh per call so it can appear on more than one tab.
  Widget? _banner(MowerAccount? acct) {
    if (acct == null) return null;
    if (acct.actionRequired) return _ActionRequiredBanner(onTap: _openPayouts);
    if (!acct.connectOnboarded) return _SetupPayoutsBanner(onTap: _openPayouts);
    if (!acct.approved) return const _PendingBanner();
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          _buildHomeTab(),
          _buildJobsTab(),
          MowerEarningsScreen(onOpenPayouts: _openPayouts),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.grass_outlined),
            selectedIcon: Icon(Icons.grass_rounded),
            label: 'Jobs',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet_rounded),
            label: 'Earnings',
          ),
        ],
      ),
    );
  }

  Widget _buildHomeTab() {
    final acct = _account;
    final banner = _banner(acct);
    return Scaffold(
      appBar: AppBar(
        title: const Text('MOWR'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Sign out',
            onPressed: _signOut,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                ?banner,
                Expanded(
                  child: acct == null
                      ? Center(child: Text(_error ?? 'Could not load'))
                      : MowerDashboard(
                          stats: _dashboard,
                          balance: _balance,
                          account: acct,
                          onBrowseAvailable: _browseAvailable,
                          onOpenJob: _openJob,
                          onOpenPayouts: _openPayouts,
                          onRefresh: _load,
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildJobsTab() {
    final acct = _account;
    final canWork = acct?.canWork ?? false;
    final pct = acct?.commissionPct ?? 15;
    final banner = _banner(acct);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Jobs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Sign out',
            onPressed: _signOut,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                ?banner,
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<int>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: 0, label: Text('Available')),
                        ButtonSegment(value: 1, label: Text('Mine')),
                        ButtonSegment(value: 2, label: Text('History')),
                      ],
                      selected: {_jobsSegment},
                      onSelectionChanged: (s) =>
                          setState(() => _jobsSegment = s.first),
                    ),
                  ),
                ),
                Expanded(
                  child: IndexedStack(
                    index: _jobsSegment,
                    children: [
                      _JobList(
                        jobs: _available,
                        emptyText: canWork
                            ? 'No jobs available right now. Pull down to refresh.'
                            : 'Finish payout setup and approval to accept jobs.',
                        onRefresh: _load,
                        onAccept: _accept,
                        showAccept: canWork,
                        error: _error,
                        commissionPct: pct,
                      ),
                      _JobList(
                        jobs: _mine,
                        emptyText: 'You haven’t accepted any jobs yet.',
                        onRefresh: _load,
                        onAccept: null,
                        showAccept: false,
                        error: _error,
                        commissionPct: pct,
                        onTap: (job) => _openJob(job.bookingId),
                      ),
                      _JobList(
                        jobs: _history,
                        emptyText: 'Completed jobs will show here.',
                        onRefresh: _load,
                        onAccept: null,
                        showAccept: false,
                        error: _error,
                        commissionPct: pct,
                        completed: true,
                        onTap: (job) => _openJob(job.bookingId),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _ActionRequiredBanner extends StatelessWidget {
  const _ActionRequiredBanner({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.orange.shade700,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Row(
            children: [
              const Icon(Icons.gpp_maybe_rounded, size: 20, color: Colors.white),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Action needed on your payouts — Stripe needs more info. '
                  'Tap to finish verification.',
                  style: TextStyle(fontSize: 12, color: Colors.white),
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

class _SetupPayoutsBanner extends StatelessWidget {
  const _SetupPayoutsBanner({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.primaryContainer,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Row(
            children: [
              Icon(Icons.account_balance_rounded,
                  size: 20, color: cs.onPrimaryContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Set up payouts to start earning — add your bank details to '
                  'finish becoming a MOWR.',
                  style: TextStyle(fontSize: 12, color: cs.onPrimaryContainer),
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

class _PendingBanner extends StatelessWidget {
  const _PendingBanner();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: cs.tertiaryContainer.withValues(alpha: 0.5),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          const Icon(Icons.hourglass_top_rounded, size: 18),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Your mower account is awaiting approval. You’ll be able to '
              'accept jobs once you’re approved.',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _JobList extends StatelessWidget {
  const _JobList({
    required this.jobs,
    required this.emptyText,
    required this.onRefresh,
    required this.onAccept,
    required this.showAccept,
    required this.error,
    required this.commissionPct,
    this.onTap,
    this.completed = false,
  });

  final List<MowerJob> jobs;
  final String emptyText;
  final Future<void> Function() onRefresh;
  final Future<void> Function(MowerJob)? onAccept;
  final bool showAccept;
  final String? error;
  final double commissionPct;
  final void Function(MowerJob)? onTap;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: jobs.isEmpty
          ? ListView(
              children: [
                const SizedBox(height: 80),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      error ?? emptyText,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ),
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: jobs.length,
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _JobCard(
                  job: jobs[i],
                  completed: completed,
                  commissionPct: commissionPct,
                  onAccept:
                      showAccept && onAccept != null ? () => onAccept!(jobs[i]) : null,
                  onTap: onTap == null ? null : () => onTap!(jobs[i]),
                ),
              ),
            ),
    );
  }
}

class _JobCard extends StatelessWidget {
  const _JobCard({
    required this.job,
    required this.onAccept,
    required this.commissionPct,
    this.onTap,
    this.completed = false,
  });

  final MowerJob job;
  final VoidCallback? onAccept;
  final double commissionPct;
  final VoidCallback? onTap;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Use the settled payout on completed jobs; estimate it otherwise.
    final actualEarned = completed ? job.mowerAmount : null;
    final earned =
        actualEarned ?? job.totalAmount * (1 - commissionPct / 100);
    final showFee = actualEarned == null;
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    job.addressLine,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '£${job.totalAmount.toStringAsFixed(2)}',
                  style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      color: cs.primary),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 14,
              runSpacing: 4,
              children: [
                _meta(Icons.grass_rounded,
                    '${job.lawnCount} lawn${job.lawnCount == 1 ? '' : 's'} · ${job.totalArea.toStringAsFixed(0)} m²'),
                _meta(Icons.event_rounded, job.whenLabel),
                if (completed)
                  _meta(Icons.check_circle_rounded, 'Completed')
                else
                  _meta(
                    job.accessProvided == true
                        ? Icons.lock_open_rounded
                        : Icons.person_rounded,
                    job.accessProvided == true ? 'Access provided' : 'Customer home',
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.payments_rounded, size: 15, color: cs.primary),
                const SizedBox(width: 4),
                Text(
                  'You ${completed ? 'earned' : 'earn'} '
                  '£${earned.toStringAsFixed(2)}',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: cs.primary),
                ),
                if (showFee) ...[
                  const SizedBox(width: 6),
                  Text('after ${commissionPct.toStringAsFixed(0)}% fee',
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                ],
              ],
            ),
            if (onAccept != null) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: onAccept,
                icon: const Icon(Icons.check_rounded),
                label: const Text('Accept job'),
              ),
            ],
          ],
        ),
        ),
      ),
    );
  }

  Widget _meta(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: Colors.grey.shade600),
        const SizedBox(width: 4),
        Text(text,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
      ],
    );
  }
}
