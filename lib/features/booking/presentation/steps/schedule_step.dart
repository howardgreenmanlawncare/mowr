import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/booking_draft.dart';
import '../../providers/booking_draft_provider.dart';
import '../booking_shell.dart';
import 'review_step.dart';

class ScheduleStepScreen extends ConsumerWidget {
  const ScheduleStepScreen({super.key});

  static const routePath = '/booking/schedule';

  Future<void> _pickDate(BuildContext context, WidgetRef ref) async {
    final now = DateTime.now();
    final existing = ref.read(bookingDraftProvider).scheduledDate;
    final initial = (existing == null || existing.isBefore(now))
        ? now.add(const Duration(days: 1))
        : existing;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: now,
      lastDate: now.add(const Duration(days: 60)),
    );
    if (picked != null) {
      ref.read(bookingDraftProvider.notifier).setScheduledDate(picked);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final draft = ref.watch(bookingDraftProvider);
    final notifier = ref.read(bookingDraftProvider.notifier);
    final ready = draft.accessProvided != null;

    return BookingShell(
      stepIndex: kStepSchedule,
      stepLabel: 'Date & time',
      bottomBar: _BottomBar(
        onContinue:
            ready ? () => context.push(ReviewStepScreen.routePath) : null,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'When would you like it done?',
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w900, height: 1.1),
          ),
          const SizedBox(height: 16),
          _ChoiceCard(
            icon: Icons.bolt_rounded,
            title: 'As soon as possible',
            subtitle: 'We’ll assign the next available mower.',
            selected: draft.asap,
            onTap: notifier.setAsap,
          ),
          const SizedBox(height: 10),
          _ChoiceCard(
            icon: Icons.event_rounded,
            title: 'Choose a date',
            subtitle: draft.asap || draft.scheduledDate == null
                ? 'Pick a specific day'
                : _formatDate(draft.scheduledDate!),
            selected: !draft.asap,
            onTap: () => _pickDate(context, ref),
          ),
          if (!draft.asap) ...[
            const SizedBox(height: 24),
            Text('Preferred time', style: theme.textTheme.labelLarge),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final w in TimeWindow.values)
                  ChoiceChip(
                    label: Text(_windowLabel(w)),
                    selected: draft.timeWindow == w,
                    onSelected: (_) => notifier.setTimeWindow(w),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          Text(
            'Will you be home to let the mower in?',
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: 10),
          _ChoiceCard(
            icon: Icons.person_rounded,
            title: "Yes, I'll be home",
            subtitle: 'The mower will need you there to get access.',
            selected: draft.accessProvided == false,
            onTap: () => notifier.setAccessProvided(false),
          ),
          const SizedBox(height: 10),
          _ChoiceCard(
            icon: Icons.lock_open_rounded,
            title: 'No — access is available',
            subtitle: 'Gate left open or open frontage — no need to be in.',
            selected: draft.accessProvided == true,
            onTap: () => notifier.setAccessProvided(true),
          ),
        ],
      ),
    );
  }
}

String _windowLabel(TimeWindow w) => switch (w) {
      TimeWindow.any => 'Any time',
      TimeWindow.morning => 'Morning',
      TimeWindow.afternoon => 'Afternoon',
      TimeWindow.evening => 'Evening',
    };

String _formatDate(DateTime d) {
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${days[d.weekday - 1]}, ${d.day} ${months[d.month - 1]}';
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      color: selected ? cs.primaryContainer.withValues(alpha: 0.5) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: selected ? cs.primary : Colors.grey.shade200,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: cs.primaryContainer,
                child: Icon(icon, color: cs.onPrimaryContainer),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: TextStyle(
                            color: Colors.grey.shade600, fontSize: 13)),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_circle_rounded, color: cs.primary),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.onContinue});

  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (onContinue == null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Let us know about access to continue',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            FilledButton.icon(
              onPressed: onContinue,
              icon: const Icon(Icons.receipt_long_rounded),
              label: const Text('See price'),
            ),
          ],
        ),
      ),
    );
  }
}
