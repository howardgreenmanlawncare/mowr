import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/data/auth_repository.dart';
import '../../payment/presentation/payment_methods_screen.dart';
import 'my_bookings_screen.dart';

/// The customer's top-level tabs.
///
/// Mirrors the mower's Home / Jobs / Earnings bar so both roles navigate the
/// same way. Added because a customer arriving at `/bookings` from the
/// confirmation screen or from sign-in had no way back: both use `context.go`,
/// which replaces the stack, so there was no back button and no other exit.
enum CustomerTab {
  home,
  bookings,
  payment;

  String get route => switch (this) {
        CustomerTab.home => '/',
        CustomerTab.bookings => MyBookingsScreen.routePath,
        CustomerTab.payment => PaymentMethodsScreen.routePath,
      };
}

/// Drop into a `Scaffold.bottomNavigationBar` on any customer top-level screen.
///
/// Only shown while signed in — a guest has no bookings or saved payment to
/// navigate to, and the booking flow gives guests their own way forward. When
/// signed out this collapses to nothing rather than showing dead tabs.
///
/// Uses `go` rather than `push` so the tabs stay a flat set — tapping between
/// them can't build a back stack of half a dozen screens.
class CustomerNavBar extends ConsumerWidget {
  const CustomerNavBar({super.key, required this.current});

  final CustomerTab current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(isSignedInProvider)) return const SizedBox.shrink();

    return NavigationBar(
      selectedIndex: current.index,
      onDestinationSelected: (i) {
        final tab = CustomerTab.values[i];
        if (tab == current) return;
        context.go(tab.route);
      },
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home_rounded),
          label: 'Home',
        ),
        NavigationDestination(
          icon: Icon(Icons.receipt_long_outlined),
          selectedIcon: Icon(Icons.receipt_long_rounded),
          label: 'Bookings',
        ),
        NavigationDestination(
          icon: Icon(Icons.credit_card_outlined),
          selectedIcon: Icon(Icons.credit_card_rounded),
          label: 'Payment',
        ),
      ],
    );
  }
}
