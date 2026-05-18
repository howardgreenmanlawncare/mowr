import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/booking/presentation/steps/postcode_step.dart';
import '../../features/booking/presentation/steps/address_step.dart';
import '../../features/booking/presentation/steps/saved_properties_step.dart';
import '../../features/booking/presentation/steps/lawn_selection_step.dart';
import '../../features/booking/presentation/steps/lawn_step.dart';
import '../../features/booking/presentation/steps/grass_height_step.dart';
import '../../features/booking/presentation/steps/lawn_access_step.dart';
import '../../features/booking/presentation/steps/condition_photos_step.dart';
import '../../features/booking/presentation/steps/service_step.dart';
import '../../features/booking/presentation/steps/schedule_step.dart';
import '../../features/booking/presentation/steps/review_step.dart';
import '../../features/booking/presentation/steps/confirmation_step.dart';

final router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const _HomeScreen(),
    ),

    // Booking flow — returning-customer path
    GoRoute(
      path: SavedPropertiesStepScreen.routePath,
      builder: (context, state) => const SavedPropertiesStepScreen(),
    ),
    GoRoute(
      path: LawnSelectionStepScreen.routePath,
      builder: (context, state) => const LawnSelectionStepScreen(),
    ),

    // Booking flow — guest path (and shared steps from grass height onward)
    GoRoute(
      path: PostcodeStepScreen.routePath,
      builder: (context, state) => const PostcodeStepScreen(),
    ),
    GoRoute(
      path: AddressStepScreen.routePath,
      builder: (context, state) => const AddressStepScreen(),
    ),
    GoRoute(
      path: LawnStepScreen.routePath,
      builder: (context, state) => const LawnStepScreen(),
    ),
    GoRoute(
      path: GrassHeightStepScreen.routePath,
      builder: (context, state) => const GrassHeightStepScreen(),
    ),
    GoRoute(
      path: LawnAccessStepScreen.routePath,
      builder: (context, state) => const LawnAccessStepScreen(),
    ),
    GoRoute(
      path: ConditionPhotosStepScreen.routePath,
      builder: (context, state) => const ConditionPhotosStepScreen(),
    ),
    GoRoute(
      path: ServiceStepScreen.routePath,
      builder: (context, state) => const ServiceStepScreen(),
    ),
    GoRoute(
      path: ScheduleStepScreen.routePath,
      builder: (context, state) => const ScheduleStepScreen(),
    ),
    GoRoute(
      path: ReviewStepScreen.routePath,
      builder: (context, state) => const ReviewStepScreen(),
    ),
    GoRoute(
      path: ConfirmationStepScreen.routePath,
      builder: (context, state) => const ConfirmationStepScreen(),
    ),

    // Lawn-creation entry point — placeholder until Phase 2 map/polygon work.
    GoRoute(
      path: '/booking/add-lawn-area',
      builder: (context, state) => const _AddLawnAreaPlaceholder(),
    ),
  ],
);

class _HomeScreen extends StatelessWidget {
  const _HomeScreen();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 36,
                backgroundColor: cs.primaryContainer,
                child: Icon(Icons.grass_rounded, size: 40, color: cs.onPrimaryContainer),
              ),
              const SizedBox(height: 20),
              Text(
                'MOWR',
                style: TextStyle(
                  color: cs.primary,
                  fontWeight: FontWeight.w900,
                  fontSize: 32,
                  letterSpacing: 4,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'On-demand lawn mowing',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 48),
              FilledButton.icon(
                onPressed: () => context.push(SavedPropertiesStepScreen.routePath),
                icon: const Icon(Icons.home_rounded),
                label: const Text('Returning customer'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => context.push(PostcodeStepScreen.routePath),
                icon: const Icon(Icons.calendar_month_rounded),
                label: const Text('Book as guest'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddLawnAreaPlaceholder extends StatelessWidget {
  const _AddLawnAreaPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add lawn area')),
      body: Center(
        child: Text(
          'Lawn-creation (draw boundary)\nPhase 2+',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ),
    );
  }
}
