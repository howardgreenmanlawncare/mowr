import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/ui.dart';
import '../../auth/presentation/sign_in_screen.dart';
import '../../booking/presentation/customer_nav_bar.dart';
import '../../mower/presentation/mower_auth_screen.dart';
import 'email_capture_screen.dart';

/// The front door. Sells the outcome and drives straight to the "see your
/// price" flow — no sign-up wall (the account is created at the payment step).
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  static const routePath = '/';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      bottomNavigationBar: const CustomerNavBar(current: CustomerTab.home),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _BrandMark(),
              const SizedBox(height: 34),
              const Eyebrow('Vetted local mowers'),
              const SizedBox(height: 12),
              Text('Lawn mowing,\non demand.',
                  style: theme.textTheme.headlineMedium),
              const SizedBox(height: 12),
              Text(
                'Draw your lawn, get an instant price, and book a vetted local '
                'mower. Pay only when it’s done.',
                style: theme.textTheme.bodyLarge
                    ?.copyWith(color: AppColors.textSecondary),
              ),
              const Hairline(),
              const _Steps(),
              const SizedBox(height: 22),
              FilledButton(
                onPressed: () => context.push(EmailCaptureScreen.routePath),
                child: const Text('Book a MOWR'),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: () => context.push(SignInScreen.routePath),
                child: const Text('Sign in'),
              ),
              const SizedBox(height: 22),
              _LinkRow(
                label: 'Become a MOWR',
                onTap: () => context.push(MowerAuthScreen.routePath),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Image.asset(
        'assets/brand/mowr_wordmark.png',
        height: 28,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}

class _Steps extends StatelessWidget {
  const _Steps();

  @override
  Widget build(BuildContext context) {
    const items = [
      ('01', 'Map your lawn', 'Trace it on the map — measured exactly.'),
      ('02', 'Get an instant price', 'Clear and upfront. No haggling.'),
      ('03', 'A local mower turns up', 'Pay only once it’s done.'),
    ];
    return Column(
      children: [
        for (var i = 0; i < items.length; i++)
          _Step(
            index: items[i].$1,
            title: items[i].$2,
            subtitle: items[i].$3,
            topBorder: i > 0,
          ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.index,
    required this.title,
    required this.subtitle,
    required this.topBorder,
  });

  final String index;
  final String title;
  final String subtitle;
  final bool topBorder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: topBorder
          ? const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.border)))
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 26,
            child: Text(index,
                style: theme.textTheme.labelMedium?.copyWith(
                    color: AppColors.green,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(subtitle, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            Expanded(
                child: Text(label,
                    style: theme.textTheme.bodyLarge)),
            const Icon(Icons.arrow_forward,
                size: 18, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
