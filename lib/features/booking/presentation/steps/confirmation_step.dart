import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../booking_shell.dart';

class ConfirmationStepScreen extends StatelessWidget {
  const ConfirmationStepScreen({super.key});

  static const routePath = '/booking/confirmation';

  @override
  Widget build(BuildContext context) {
    return BookingShell(
      stepIndex: kStepConfirmation,
      stepLabel: 'Done',
      // No onContinue — hides the Continue button on the final step.
      body: _ConfirmationPlaceholder(),
    );
  }
}

class _ConfirmationPlaceholder extends StatelessWidget {
  const _ConfirmationPlaceholder();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 32),
        Text(
          'Confirmation',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 32),
        FilledButton.icon(
          onPressed: () => context.go('/'),
          icon: const Icon(Icons.home_rounded),
          label: const Text('Back to home'),
          style: FilledButton.styleFrom(
            backgroundColor: cs.primaryContainer,
            foregroundColor: cs.onPrimaryContainer,
          ),
        ),
      ],
    );
  }
}
