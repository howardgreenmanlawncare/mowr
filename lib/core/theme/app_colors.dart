import 'package:flutter/material.dart';

/// MOWR design tokens — Swiss / International Typographic Style: ink on paper,
/// one signal green, hairline rules instead of shadows. Roughly 80% paper/ink,
/// green reserved as a *signal*: the primary action, a selected option, live job
/// progress, successful completion, an available service. Nothing decorative.
///
/// Never hard-code these values in widgets — reference `AppColors` or, better,
/// the `ColorScheme` / `TextTheme` built from them in `AppTheme`.
abstract final class AppColors {
  // Neutrals — warm-neutral paper, near-black ink, one graphite, one hairline.
  static const Color background = Color(0xFFF5F5F2); // paper
  static const Color surface = Color(0xFFFFFFFF); // card / sheet
  static const Color textPrimary = Color(0xFF121211); // ink
  static const Color textSecondary = Color(0xFF6E6E69); // graphite
  static const Color border = Color(0xFFE3E3DE); // hairline

  /// A quiet neutral fill for inert chips/tiles (not green — green is a signal).
  static const Color neutralFill = Color(0xFFEDEDE8);

  // Brand green — rationed, used for meaning only.
  static const Color green = Color(0xFF2E6A43);
  static const Color greenDark = Color(0xFF1F4C30);
  static const Color greenPale = Color(0xFFE9F0EA);

  // Status semantics — muted, never competing with the green signal.
  static const Color warning = Color(0xFFC98A2B);
  static const Color warningPale = Color(0xFFF7EDD9);
  static const Color warningInk = Color(0xFF8A5A12);
  static const Color error = Color(0xFFC0473E);
  static const Color errorPale = Color(0xFFF6E2E0);

  /// Seed retained for `ColorScheme.fromSeed`; it's the brand green.
  static const Color seed = green;
}
