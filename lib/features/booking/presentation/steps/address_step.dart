import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../booking_shell.dart';

class AddressStepScreen extends StatelessWidget {
  const AddressStepScreen({super.key});

  static const routePath = '/booking/address';

  @override
  Widget build(BuildContext context) {
    return BookingShell(
      stepIndex: kStepAddress,
      stepLabel: 'Address',
      onContinue: () => context.push('/booking/lawn'),
      body: const _AddressPlaceholder(),
    );
  }
}

class _AddressPlaceholder extends StatelessWidget {
  const _AddressPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Address',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
    );
  }
}
