import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/admin_repository.dart';
import 'admin_alerts_screen.dart';
import 'admin_dashboard_screen.dart';
import 'admin_mowers_screen.dart';
import 'admin_settings_screen.dart';

/// The admin home: a bottom-nav shell over the operations dashboard, the mower
/// vetting queue, the alerts inbox (chat off-app/cash flags + reliability
/// flags), and pricing/settings. This is where an admin lands after sign-in.
class AdminShell extends ConsumerStatefulWidget {
  const AdminShell({super.key});

  static const routePath = '/admin';

  @override
  ConsumerState<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends ConsumerState<AdminShell> {
  int _index = 0;
  int _openAlerts = 0;

  @override
  void initState() {
    super.initState();
    _refreshBadge();
  }

  Future<void> _refreshBadge() async {
    final n = await ref.read(adminRepositoryProvider).openTicketCount();
    if (mounted) setState(() => _openAlerts = n);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          const AdminDashboardScreen(),
          const AdminMowersScreen(),
          AdminAlertsScreen(onChanged: _refreshBadge),
          const AdminSettingsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) {
          setState(() => _index = i);
          if (i == 2) _refreshBadge();
        },
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Dashboard',
          ),
          const NavigationDestination(
            icon: Icon(Icons.people_outline_rounded),
            selectedIcon: Icon(Icons.people_rounded),
            label: 'Mowers',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: _openAlerts > 0,
              label: Text('$_openAlerts'),
              child: const Icon(Icons.notifications_none_rounded),
            ),
            selectedIcon: Badge(
              isLabelVisible: _openAlerts > 0,
              label: Text('$_openAlerts'),
              child: const Icon(Icons.notifications_rounded),
            ),
            label: 'Alerts',
          ),
          const NavigationDestination(
            icon: Icon(Icons.tune_rounded),
            selectedIcon: Icon(Icons.tune_rounded),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
