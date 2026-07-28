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
import '../../features/admin/presentation/admin_settings_screen.dart';
import '../../features/admin/presentation/admin_shell.dart';
import '../../features/booking/presentation/my_bookings_screen.dart';
import '../../features/booking/presentation/booking_status_screen.dart';
import '../../features/assistant/presentation/assistant_screen.dart';
import '../../features/chat/presentation/chat_screen.dart';
import '../../features/auth/presentation/sign_in_screen.dart';
import '../../features/onboarding/presentation/splash_screen.dart';
import '../../features/onboarding/presentation/welcome_screen.dart';
import '../../features/onboarding/presentation/email_capture_screen.dart';
import '../../features/payment/presentation/payment_methods_screen.dart';
import '../../features/mower/presentation/mower_auth_screen.dart';
import '../../features/mower/presentation/mower_home_screen.dart';
import '../../features/mower/presentation/mower_job_detail_screen.dart';
import '../../features/mower/presentation/mower_remeasure_screen.dart';
import '../../features/mower/presentation/mower_earnings_screen.dart';
import '../../features/mower/presentation/mower_payouts_screen.dart';
import '../../features/mower/presentation/mower_route_screen.dart';
import '../../features/mower/presentation/mower_verify_phone_screen.dart';

final router = GoRouter(
  initialLocation: SplashScreen.routePath,
  routes: [
    GoRoute(
      path: SplashScreen.routePath,
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(
      path: '/',
      builder: (context, state) => const WelcomeScreen(),
    ),
    GoRoute(
      path: EmailCaptureScreen.routePath,
      builder: (context, state) => const EmailCaptureScreen(),
    ),
    GoRoute(
      path: SignInScreen.routePath,
      builder: (context, state) => const SignInScreen(),
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
      // '?next=/bookings' turns this into a standalone sign-in that returns
      // there instead of continuing into the booking flow's payment step.
      builder: (context, state) =>
          AccountStepScreen(nextRoute: state.uri.queryParameters['next']),
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

    // Merged AI assistant — support Q&A + record actions + booking hand-off.
    GoRoute(
      path: AssistantScreen.routePath,
      builder: (context, state) => const AssistantScreen(),
    ),

    // Customer post-booking. '/bookings/:id' is where an on-site re-measure
    // gets approved, so it must stay reachable after checkout.
    GoRoute(
      path: MyBookingsScreen.routePath,
      builder: (context, state) => const MyBookingsScreen(),
    ),
    GoRoute(
      path: '${BookingStatusScreen.routeBase}/:id',
      builder: (context, state) =>
          BookingStatusScreen(bookingId: state.pathParameters['id']!),
    ),

    // Live customer↔mower chat (open while a job is under way). Shared by both
    // sides; the send RPC enforces participation + the open window server-side.
    GoRoute(
      path: '/chat/:id',
      builder: (context, state) => ChatScreen(
        bookingId: state.pathParameters['id']!,
        title: state.uri.queryParameters['title'],
      ),
    ),

    // Mower side
    // Admin. There is deliberately no in-app way to become an admin — the role
    // is set on the profile row by hand (see migration 0013).
    GoRoute(
      path: AdminShell.routePath,
      builder: (context, state) => const AdminShell(),
    ),
    GoRoute(
      path: AdminSettingsScreen.routePath,
      builder: (context, state) => const AdminSettingsScreen(),
    ),

    GoRoute(
      path: MowerAuthScreen.routePath,
      builder: (context, state) => const MowerAuthScreen(),
    ),
    GoRoute(
      path: MowerHomeScreen.routePath,
      builder: (context, state) => const MowerHomeScreen(),
    ),
    GoRoute(
      path: '/mower/job/:id',
      builder: (context, state) =>
          MowerJobDetailScreen(bookingId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/mower/job/:id/remeasure',
      builder: (context, state) =>
          MowerRemeasureScreen(bookingId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: MowerEarningsScreen.routePath,
      builder: (context, state) => const MowerEarningsScreen(),
    ),
    GoRoute(
      path: MowerPayoutsScreen.routePath,
      builder: (context, state) => const MowerPayoutsScreen(),
    ),
    GoRoute(
      path: MowerVerifyPhoneScreen.routePath,
      builder: (context, state) => const MowerVerifyPhoneScreen(),
    ),
    GoRoute(
      path: MowerRouteScreen.routePath,
      builder: (context, state) => const MowerRouteScreen(),
    ),
  ],
);


