import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../booking_shell.dart';

class ServiceStepScreen extends StatelessWidget {
  const ServiceStepScreen({super.key});

  static const routePath = '/booking/service';

  @override
  Widget build(BuildContext context) {
    return BookingShell(
      stepIndex: kStepService,
      stepLabel: 'Service & extras',
      onContinue: () => context.push('/booking/schedule'),
      body: const _ServicePlaceholder(),
    );
  }
}

class _ServicePlaceholder extends StatelessWidget {
  const _ServicePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Service & extras',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
    );
  }
}
