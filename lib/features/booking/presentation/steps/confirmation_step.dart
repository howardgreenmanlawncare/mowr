import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/booking_draft_provider.dart';
import '../booking_shell.dart';

class ConfirmationStepScreen extends ConsumerWidget {
  const ConfirmationStepScreen({super.key});

  static const routePath = '/booking/confirmation';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return BookingShell(
      stepIndex: kStepConfirmation,
      stepLabel: 'All set',
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 24),
          CircleAvatar(
            radius: 44,
            backgroundColor: cs.primaryContainer,
            child: Icon(Icons.check_rounded,
                size: 52, color: cs.onPrimaryContainer),
          ),
          const SizedBox(height: 24),
          Text(
            'You’re all set!',
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'Your booking is confirmed and we’re finding you a vetted local '
              'mower. We’ll email you as soon as it’s accepted — and you’re '
              'only charged once the job is done.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: Colors.grey.shade700, height: 1.4),
            ),
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: () {
              ref.read(bookingDraftProvider.notifier).reset();
              context.go('/');
            },
            icon: const Icon(Icons.home_rounded),
            label: const Text('Back to home'),
          ),
        ],
      ),
    );
  }
}
