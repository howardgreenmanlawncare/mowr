import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/data/auth_repository.dart';
import '../data/mower_repository.dart';
import '../domain/mower_job.dart';

class MowerHomeScreen extends ConsumerStatefulWidget {
  const MowerHomeScreen({super.key});

  static const routePath = '/mower/home';

  @override
  ConsumerState<MowerHomeScreen> createState() => _MowerHomeScreenState();
}

class _MowerHomeScreenState extends ConsumerState<MowerHomeScreen> {
  bool _loading = true;
  bool _approved = false;
  List<MowerJob> _available = const [];
  List<MowerJob> _mine = const [];
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
      final approved = await repo.isApproved();
      final available = await repo.availableJobs();
      final mine = await repo.myJobs();
      if (!mounted) return;
      setState(() {
        _approved = approved;
        _available = available;
        _mine = mine;
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

  Future<void> _signOut() async {
    await ref.read(authRepositoryProvider).signOut();
    if (mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('MOWR — Jobs'),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout_rounded),
              tooltip: 'Sign out',
              onPressed: _signOut,
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Available'),
              Tab(text: 'My jobs'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  if (!_approved) const _PendingBanner(),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _JobList(
                          jobs: _available,
                          emptyText: _approved
                              ? 'No jobs available right now. Pull down to refresh.'
                              : 'Jobs appear here once your account is approved.',
                          onRefresh: _load,
                          onAccept: _accept,
                          showAccept: _approved,
                          error: _error,
                        ),
                        _JobList(
                          jobs: _mine,
                          emptyText: 'You haven’t accepted any jobs yet.',
                          onRefresh: _load,
                          onAccept: null,
                          showAccept: false,
                          error: _error,
                        ),
                      ],
                    ),
                  ),
                ],
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
  });

  final List<MowerJob> jobs;
  final String emptyText;
  final Future<void> Function() onRefresh;
  final Future<void> Function(MowerJob)? onAccept;
  final bool showAccept;
  final String? error;

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
                  onAccept:
                      showAccept && onAccept != null ? () => onAccept!(jobs[i]) : null,
                ),
              ),
            ),
    );
  }
}

class _JobCard extends StatelessWidget {
  const _JobCard({required this.job, required this.onAccept});

  final MowerJob job;
  final VoidCallback? onAccept;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    job.addressLine,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                ),
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
                _meta(
                  job.accessProvided == true
                      ? Icons.lock_open_rounded
                      : Icons.person_rounded,
                  job.accessProvided == true ? 'Access provided' : 'Customer home',
                ),
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
