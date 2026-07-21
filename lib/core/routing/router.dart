import 'package:go_router/go_router.dart';
import '../../features/booking/presentation/steps/postcode_step.dart';
import '../../features/booking/presentation/steps/address_step.dart';
import '../../features/booking/presentation/steps/saved_properties_step.dart';
import '../../features/booking/presentation/steps/lawn_selection_step.dart';
import '../../features/booking/presentation/steps/lawn_step.dart';
import '../../features/booking/presentation/steps/lawn_draw_screen.dart';
import '../../features/booking/presentation/steps/grass_height_step.dart';
import '../../features/booking/presentation/steps/lawn_access_step.dart';
import '../../features/booking/presentation/steps/condition_photos_step.dart';
import '../../features/booking/presentation/steps/service_step.dart';
import '../../features/booking/presentation/steps/schedule_step.dart';
import '../../features/booking/presentation/steps/review_step.dart';
import '../../features/booking/presentation/steps/account_step.dart';
import '../../features/booking/presentation/steps/payment_step.dart';
import '../../features/booking/presentation/steps/confirmation_step.dart';
import '../../features/onboarding/presentation/welcome_screen.dart';
import '../../features/onboarding/presentation/email_capture_screen.dart';
import '../../features/payment/presentation/payment_methods_screen.dart';

final router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const WelcomeScreen(),
    ),
    GoRoute(
      path: EmailCaptureScreen.routePath,
      builder: (context, state) => const EmailCaptureScreen(),
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
      path: LawnDrawScreen.routePath,
      builder: (context, state) => const LawnDrawScreen(),
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
      path: AccountStepScreen.routePath,
      builder: (context, state) => const AccountStepScreen(),
    ),
    GoRoute(
      path: PaymentStepScreen.routePath,
      builder: (context, state) => const PaymentStepScreen(),
    ),
    GoRoute(
      path: ConfirmationStepScreen.routePath,
      builder: (context, state) => const ConfirmationStepScreen(),
    ),
    GoRoute(
      path: PaymentMethodsScreen.routePath,
      builder: (context, state) => const PaymentMethodsScreen(),
    ),
  ],
);


