import 'package:flutter/material.dart';
import 'app_colors.dart';

abstract final class AppTheme {
  static const double _cardRadius = 24;
  static const double _buttonRadius = 18;
  static const double _inputRadius = 18;

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.seed,
      brightness: Brightness.light,
      surface: AppColors.background,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,

      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_cardRadius),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_buttonRadius),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_buttonRadius),
          ),
          side: BorderSide(color: scheme.primary),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_inputRadius),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_inputRadius),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_inputRadius),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppColors.background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(_buttonRadius)),
        ),
      ),

      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),

      appBarTheme: AppBarTheme(
        centerTitle: true,
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: scheme.onSurface,
      ),
    );
  }
}
