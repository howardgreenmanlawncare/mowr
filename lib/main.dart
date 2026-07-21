import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/routing/router.dart';
import 'core/theme/app_theme.dart';

void main() {
  runApp(const ProviderScope(child: MowrApp()));
}

class MowrApp extends StatelessWidget {
  const MowrApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'MOWR',
      theme: AppTheme.light,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        // Bump all text ~10% for readability, while still respecting the
        // device's own accessibility text-size setting. Clamped so very large
        // system settings don't break layouts.
        final mq = MediaQuery.of(context);
        final systemFactor = mq.textScaler.scale(1.0);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: TextScaler.linear(
              (systemFactor * 1.1).clamp(1.0, 1.5),
            ),
          ),
          child: child!,
        );
      },
    );
  }
}
