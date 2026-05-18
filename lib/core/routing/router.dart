import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

// Placeholder shell shown until Phase 1 screens are built.
// Replaced by real routes as each phase is implemented.
final router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const _PlaceholderScreen(),
    ),
  ],
);

class _PlaceholderScreen extends StatelessWidget {
  const _PlaceholderScreen();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.grass_rounded, size: 64, color: cs.primary),
            const SizedBox(height: 16),
            Text(
              'MOWR',
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    color: cs.primary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 4,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Phase 0 — Foundation ready',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
