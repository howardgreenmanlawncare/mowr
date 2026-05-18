import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../booking_shell.dart';
import 'grass_height_step.dart';

class LawnStepScreen extends StatelessWidget {
  const LawnStepScreen({super.key});

  static const routePath = '/booking/lawn';

  @override
  Widget build(BuildContext context) {
    return BookingShell(
      stepIndex: kStepLawn,
      stepLabel: 'Lawn details',
      onContinue: () => context.push(GrassHeightStepScreen.routePath),
      body: const _LawnPlaceholder(),
    );
  }
}

class _LawnPlaceholder extends StatelessWidget {
  const _LawnPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Lawn details',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
    );
  }
}
