import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../booking_shell.dart';

class PostcodeStepScreen extends StatelessWidget {
  const PostcodeStepScreen({super.key});

  static const routePath = '/booking/postcode';

  @override
  Widget build(BuildContext context) {
    return BookingShell(
      stepIndex: kStepPostcode,
      stepLabel: 'Postcode',
      continueLabel: 'Find address',
      onContinue: () => context.push('/booking/address'),
      body: const _PostcodePlaceholder(),
    );
  }
}

class _PostcodePlaceholder extends StatelessWidget {
  const _PostcodePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Postcode',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
    );
  }
}
