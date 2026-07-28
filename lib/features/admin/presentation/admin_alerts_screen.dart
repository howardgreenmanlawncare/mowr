import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../data/admin_repository.dart';

/// The admin alerts inbox. Surfaces support tickets — most importantly the
/// off-app / cash chat flags and mower reliability flags raised server-side
/// (migrations 0024/0025). This is the in-app "I get notified straight away"
/// surface; email (via process-notifications + Resend) is the out-of-app one.
class AdminAlertsScreen extends ConsumerStatefulWidget {
  const AdminAlertsScreen({super.key, this.onChanged});

  /// Called after a resolve, so the shell can refresh its unread badge.
  final VoidCallback? onChanged;

  static const routePath = '/admin/alerts';

  @override
  ConsumerState<AdminAlertsScreen> createState() => _AdminAlertsScreenState();
}

class _AdminAlertsScreenState extends ConsumerState<AdminAlertsScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _tickets = const [];

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
      final t = await ref.read(adminRepositoryProvider).supportTickets();
      if (!mounted) return;
      setState(() {
        _tickets = t;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().contains('Admins only')
            ? 'This account is not an admin.'
            : 'Could not load alerts.';
      });
    }
  }

  Future<void> _resolve(Map<String, dynamic> t) async {
    try {
      await ref.read(adminRepositoryProvider).resolveTicket(t['id'] as String);
      widget.onChanged?.call();
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('Could not update.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final open = _tickets.where((t) => t['status'] == 'open').length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Alerts'),
        bottom: open == 0
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(28),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '$open open',
                    style: const TextStyle(
                        color: AppColors.error, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
      ),
      body: RefreshIndicator(onRefresh: _load, child: _body()),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final text = Theme.of(context).textTheme;

    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(32, 80, 32, 32),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Text(_error!, textAlign: TextAlign.center, style: text.bodyLarge),
          const SizedBox(height: 24),
          Center(
              child: FilledButton(
                  onPressed: _load, child: const Text('Try again'))),
        ],
      );
    }

    if (_tickets.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(32, 96, 32, 32),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const Icon(Icons.notifications_none_rounded,
              size: 48, color: AppColors.textSecondary),
          const SizedBox(height: 16),
          Text('No alerts. All quiet.',
              textAlign: TextAlign.center, style: text.titleMedium),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _tickets.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) =>
          _TicketCard(ticket: _tickets[i], onResolve: () => _resolve(_tickets[i])),
    );
  }
}

class _TicketCard extends StatelessWidget {
  const _TicketCard({required this.ticket, required this.onResolve});

  final Map<String, dynamic> ticket;
  final VoidCallback onResolve;

  bool get _isFlag {
    final s = (ticket['summary'] as String? ?? '').toLowerCase();
    return s.contains('flag') || s.contains('off-app') || s.contains('cancelled');
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final open = ticket['status'] == 'open';
    final summary = ticket['summary'] as String? ?? 'Alert';
    final transcript = ticket['transcript'] as String?;
    final who = ticket['customer'] as String?;
    final when = DateTime.tryParse(ticket['created_at']?.toString() ?? '')
        ?.toLocal();

    return Card(
      margin: EdgeInsets.zero,
      color: open && _isFlag ? AppColors.errorPale : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _isFlag
                      ? Icons.flag_rounded
                      : Icons.support_agent_rounded,
                  size: 18,
                  color: open && _isFlag
                      ? AppColors.error
                      : AppColors.textSecondary,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(summary, style: text.titleSmall)),
                if (!open)
                  Text('Resolved',
                      style: text.labelSmall
                          ?.copyWith(color: AppColors.textSecondary)),
              ],
            ),
            if (transcript != null && transcript.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(transcript,
                  style: text.bodyMedium
                      ?.copyWith(color: AppColors.textPrimary)),
            ],
            const SizedBox(height: 8),
            Text(
              [
                ?who,
                if (when != null)
                  '${when.day}/${when.month} '
                      '${when.hour.toString().padLeft(2, '0')}:'
                      '${when.minute.toString().padLeft(2, '0')}',
              ].join(' · '),
              style: text.labelSmall?.copyWith(color: AppColors.textSecondary),
            ),
            if (open) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton(
                  onPressed: onResolve,
                  child: const Text('Mark resolved'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
