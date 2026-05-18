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
    );
  }
}
