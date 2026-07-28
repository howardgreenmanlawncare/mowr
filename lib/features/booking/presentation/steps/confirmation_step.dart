import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/booking_draft_provider.dart';
import '../booking_shell.dart';
import '../my_bookings_screen.dart';

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
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(Icons.check_rounded, size: 44, color: cs.primary),
          ),
          const SizedBox(height: 24),
          Text('You’re all set', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'Your booking is confirmed and we’re finding you a vetted local '
              'mower. We’ll email you as soon as it’s accepted — and you’re '
              'only charged once the job is done.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant, height: 1.4),
            ),
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: () {
              ref.read(bookingDraftProvider.notifier).reset();
              context.go(MyBookingsScreen.routePath);
            },
            icon: const Icon(Icons.receipt_long_rounded),
            label: const Text('Track my booking'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () {
              ref.read(bookingDraftProvider.notifier).reset();
              context.go('/');
            },
            child: const Text('Back to home'),
          ),
        ],
      ),
    );
  }
}
