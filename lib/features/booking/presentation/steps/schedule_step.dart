import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../booking_shell.dart';

class ScheduleStepScreen extends StatelessWidget {
  const ScheduleStepScreen({super.key});

  static const routePath = '/booking/schedule';

  @override
  Widget build(BuildContext context) {
    return BookingShell(
      stepIndex: kStepSchedule,
      stepLabel: 'Date & time',
      continueLabel: 'See price',
      onContinue: () => context.push('/booking/review'),
      body: const _SchedulePlaceholder(),
    );
  }
}

class _SchedulePlaceholder extends StatelessWidget {
  const _SchedulePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Date & time',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
    );
  }
}
