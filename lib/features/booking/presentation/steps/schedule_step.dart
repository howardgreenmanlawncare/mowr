import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  /// Lets the customer set a bespoke "every N days" repeat when the presets
  /// (weekly / 2 / 3 weeks) don't fit.
  Future<void> _pickCustomDays(
      BuildContext context, WidgetRef ref, int current) async {
    final controller = TextEditingController(
        text: (current > 0 ? current : 10).toString());
    final days = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Every how many days?'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
              labelText: 'Repeat every', suffixText: 'days'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(controller.text.trim());
              Navigator.pop(ctx, (v != null && v >= 1) ? v : null);
            },
            child: const Text('Set'),
          ),
        ],
      ),
    );
    if (days != null) {
      ref
          .read(bookingDraftProvider.notifier)
          .setRecurrence(RecurrenceInterval(days));
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
                ?.copyWith(fontWeight: FontWeight.w700, height: 1.1),
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
          Text('How often?', style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          Text(
            'Set up a repeat and keep your lawn in shape — loyalty discounts '
            'apply to recurring mows.',
            style:
                theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final r in RecurrenceInterval.presets)
                ChoiceChip(
                  label: Text(r.label),
                  selected: draft.recurrence == r,
                  onSelected: (_) => notifier.setRecurrence(r),
                ),
              ChoiceChip(
                label: Text(
                    draft.recurrence.isCustom ? draft.recurrence.label : 'Custom…'),
                selected: draft.recurrence.isCustom,
                onSelected: (_) =>
                    _pickCustomDays(context, ref, draft.recurrence.days),
              ),
            ],
          ),
          if (draft.recurrence.isRecurring) ...[
            const SizedBox(height: 20),
            Text('Preferred day', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(
              'Your repeat mows will land on this day. The first is the '
              'next one coming up.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var wd = 1; wd <= 7; wd++)
                  ChoiceChip(
                    label: Text(_weekdayLabel(wd)),
                    selected:
                        !draft.asap && draft.scheduledDate?.weekday == wd,
                    onSelected: (_) =>
                        notifier.setScheduledDate(_nextWeekday(wd)),
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

const _weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String _weekdayLabel(int weekday) => _weekdayNames[weekday - 1];

/// The next date (from tomorrow) that falls on [weekday] (1 = Mon … 7 = Sun).
DateTime _nextWeekday(int weekday) {
  final now = DateTime.now();
  var d = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
  while (d.weekday != weekday) {
    d = d.add(const Duration(days: 1));
  }
  return d;
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
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      color: selected ? cs.primaryContainer : cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? cs.primary : cs.outline,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: selected ? cs.surface : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon,
                    size: 20, color: selected ? cs.primary : cs.onSurface),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 1),
                    Text(subtitle, style: theme.textTheme.bodySmall),
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
