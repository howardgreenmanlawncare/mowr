import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../booking_shell.dart';

class ReviewStepScreen extends StatelessWidget {
  const ReviewStepScreen({super.key});

  static const routePath = '/booking/review';

  @override
  Widget build(BuildContext context) {
    return BookingShell(
      stepIndex: kStepReview,
      stepLabel: 'Review & price',
      continueLabel: 'Request booking',
      onContinue: () => context.push('/booking/confirmation'),
      body: const _ReviewPlaceholder(),
    );
  }
}

class _ReviewPlaceholder extends StatelessWidget {
  const _ReviewPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Review & price',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
    );
  }
}
