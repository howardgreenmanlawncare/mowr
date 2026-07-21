import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../booking/presentation/steps/saved_properties_step.dart';
import 'email_capture_screen.dart';

/// The front door. Sells the outcome and drives straight to the "see your
/// price" flow — no sign-up wall (the account is created at the payment step).
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              Center(
                child: CircleAvatar(
                  radius: 34,
                  backgroundColor: cs.primaryContainer,
                  child: Icon(Icons.grass_rounded,
                      size: 38, color: cs.onPrimaryContainer),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  'MOWR',
                  style: TextStyle(
                    color: cs.primary,
                    fontWeight: FontWeight.w900,
                    fontSize: 30,
                    letterSpacing: 4,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'Lawn mowing,\non demand.',
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Draw your lawn, see your price in seconds, and book a vetted '
                'local mower. No waiting around for quotes.',
                style: theme.textTheme.bodyLarge
                    ?.copyWith(color: Colors.grey.shade700, height: 1.4),
              ),
              const SizedBox(height: 28),
              const _HowItWorks(),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: () => context.push(EmailCaptureScreen.routePath),
                icon: const Icon(Icons.arrow_forward_rounded),
                label: const Text('See my price'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () =>
                    context.push(SavedPropertiesStepScreen.routePath),
                child: const Text("I've booked before"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: const [
        _Step(
          number: '1',
          icon: Icons.draw_rounded,
          title: 'Map your lawn',
          subtitle: 'Trace it on the map — we measure it exactly.',
        ),
        SizedBox(height: 14),
        _Step(
          number: '2',
          icon: Icons.receipt_long_rounded,
          title: 'Get an instant price',
          subtitle: 'A clear, upfront price. No haggling.',
        ),
        SizedBox(height: 14),
        _Step(
          number: '3',
          icon: Icons.grass_rounded,
          title: 'A local mower does the job',
          subtitle: 'Pay only once it’s done.',
        ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final String number;
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: cs.primaryContainer.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: cs.primary),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style:
                      TextStyle(color: Colors.grey.shade600, fontSize: 13)),
            ],
          ),
        ),
      ],
    );
  }
}
