import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// The single source of ThemeData. Swiss / International Typographic Style:
/// warm-paper grounds, hairline rules instead of shadows, rationed green, and
/// Arimo — metric-compatible with Helvetica — on a disciplined type scale where
/// hierarchy comes from size, weight and space, not decoration.
abstract final class AppTheme {
  static const double _radius = 5; // crisp: cards, buttons, inputs
  static const double _sheetRadius = 12;

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.seed,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppColors.green,
      onPrimary: Colors.white,
      primaryContainer: AppColors.greenPale,
      onPrimaryContainer: AppColors.greenDark,
      secondary: AppColors.green,
      onSecondary: Colors.white,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      onSurfaceVariant: AppColors.textSecondary,
      surfaceContainerLowest: AppColors.surface,
      surfaceContainerLow: AppColors.background,
      surfaceContainer: AppColors.background,
      surfaceContainerHigh: AppColors.neutralFill,
      surfaceContainerHighest: AppColors.neutralFill,
      outline: AppColors.border,
      outlineVariant: AppColors.border,
      error: AppColors.error,
      onError: Colors.white,
      errorContainer: AppColors.errorPale,
      onErrorContainer: AppColors.error,
      secondaryContainer: AppColors.greenPale,
      onSecondaryContainer: AppColors.greenDark,
      tertiaryContainer: AppColors.warningPale,
      onTertiaryContainer: AppColors.warningInk,
    );

    final base = ThemeData(useMaterial3: true, colorScheme: scheme);

    // Arimo (Helvetica-compatible) on a Swiss type scale. Letter-spacing is in
    // logical pixels; headlines tighten, uppercase micro-labels open up.
    final t = GoogleFonts.arimoTextTheme(base.textTheme);
    final text = t.copyWith(
      headlineLarge: t.headlineLarge?.copyWith(
          fontSize: 34, fontWeight: FontWeight.w700, letterSpacing: -0.9,
          height: 1.03, color: AppColors.textPrimary),
      headlineMedium: t.headlineMedium?.copyWith(
          fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: -0.7,
          height: 1.05, color: AppColors.textPrimary),
      headlineSmall: t.headlineSmall?.copyWith(
          fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.45,
          height: 1.08, color: AppColors.textPrimary),
      titleLarge: t.titleLarge?.copyWith(
          fontSize: 19, fontWeight: FontWeight.w600, letterSpacing: -0.25,
          color: AppColors.textPrimary),
      titleMedium: t.titleMedium?.copyWith(
          fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.1,
          color: AppColors.textPrimary),
      titleSmall: t.titleSmall?.copyWith(
          fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
      bodyLarge: t.bodyLarge?.copyWith(
          fontSize: 15, height: 1.45, color: AppColors.textPrimary),
      bodyMedium: t.bodyMedium?.copyWith(
          fontSize: 14, height: 1.45, color: AppColors.textPrimary),
      bodySmall: t.bodySmall?.copyWith(
          fontSize: 13, height: 1.4, color: AppColors.textSecondary),
      labelLarge: t.labelLarge?.copyWith(
          fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 0),
      labelMedium: t.labelMedium?.copyWith(
          fontSize: 12, fontWeight: FontWeight.w600),
      // Canonical eyebrow: screens uppercase the string themselves.
      labelSmall: t.labelSmall?.copyWith(
          fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.4,
          color: AppColors.textSecondary),
    );

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      textTheme: text,

      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radius),
          side: const BorderSide(color: AppColors.border),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.green,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.neutralFill,
          disabledForegroundColor: AppColors.textSecondary,
          minimumSize: const Size.fromHeight(52),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_radius),
          ),
          textStyle: text.labelLarge,
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_radius),
          ),
          side: const BorderSide(color: AppColors.border),
          textStyle: text.labelLarge,
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.green,
          textStyle: text.labelLarge,
        ),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: AppColors.textPrimary),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radius),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radius),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radius),
          borderSide: const BorderSide(color: AppColors.green, width: 1.5),
        ),
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        hintStyle: const TextStyle(color: AppColors.textSecondary),
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(_sheetRadius)),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_sheetRadius),
        ),
      ),

      // Status pills — hairline outline on paper, uppercase. Only meaningful
      // states use them; green fill is reserved for live/available.
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surface,
        side: const BorderSide(color: AppColors.border),
        labelStyle: text.labelSmall?.copyWith(
            fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.8,
            color: AppColors.textSecondary),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),

      dividerTheme: const DividerThemeData(
        color: AppColors.border, thickness: 1, space: 1,
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 66,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
              size: 22,
              color: s.contains(WidgetState.selected)
                  ? AppColors.green
                  : AppColors.textSecondary,
            )),
        labelTextStyle: WidgetStateProperty.resolveWith((s) =>
            text.labelSmall!.copyWith(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
              color: s.contains(WidgetState.selected)
                  ? AppColors.green
                  : AppColors.textSecondary,
            )),
      ),

      // Left-aligned app bars read faster in a utility app.
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: AppColors.textPrimary,
        titleTextStyle: text.titleLarge,
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.all(Colors.white),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected)
                ? AppColors.green
                : const Color(0xFFCFCFC8)),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
    );
  }
}
