import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_spacing.dart';

/// Centralized ERP theme. All color comes from [AppColors].
/// Typography uses bundled Cairo with RTL-friendly defaults.
abstract final class AppTheme {
  static const String fontFamily = 'Cairo';

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      surface: AppColors.surface,
    ).copyWith(
      primary: AppColors.primary,
      onPrimary: Colors.white,
      primaryContainer: AppColors.primaryContainer,
      secondary: AppColors.primaryDark,
      surface: AppColors.surface,
      error: AppColors.danger,
      outlineVariant: AppColors.divider,
    );
    return _build(scheme, isDark: false);
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.dark,
      surface: AppColors.darkSurface,
    ).copyWith(
      primary: AppColors.darkPrimary,
      onPrimary: AppColors.darkBackground,
      surface: AppColors.darkSurface,
      error: const Color(0xFFF87171),
      outlineVariant: AppColors.darkDivider,
    );
    return _build(scheme, isDark: true);
  }

  static ThemeData _build(ColorScheme scheme, {required bool isDark}) {
    final textColor =
        isDark ? AppColors.darkText : AppColors.text;
    final secondary =
        isDark ? AppColors.darkSecondaryText : AppColors.secondaryText;

    TextStyle style({
      required double size,
      required FontWeight weight,
      double height = 1.5,
      Color? color,
    }) =>
        TextStyle(
          fontFamily: fontFamily,
          fontSize: size,
          fontWeight: weight,
          height: height,
          color: color ?? textColor,
        );

    final textTheme = TextTheme(
      displayLarge: style(size: 50, weight: FontWeight.w800, height: 1.1),
      displayMedium: style(size: 32, weight: FontWeight.w800, height: 1.2),
      headlineLarge: style(size: 26, weight: FontWeight.w800, height: 1.3),
      headlineMedium: style(size: 20, weight: FontWeight.w800, height: 1.4),
      headlineSmall: style(size: 18, weight: FontWeight.w800, height: 1.4),
      titleLarge: style(size: 16, weight: FontWeight.w800),
      titleMedium: style(size: 15, weight: FontWeight.w800),
      titleSmall: style(size: 14, weight: FontWeight.w700),
      bodyLarge: style(size: 14, weight: FontWeight.w600),
      bodyMedium: style(size: 13, weight: FontWeight.w600),
      bodySmall: style(size: 12, weight: FontWeight.w400, color: secondary),
      labelLarge: style(size: 13, weight: FontWeight.w700),
      labelMedium: style(size: 12, weight: FontWeight.w600),
      labelSmall:
          style(size: 11, weight: FontWeight.w600, color: secondary),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: fontFamily,
      scaffoldBackgroundColor:
          isDark ? AppColors.darkBackground : AppColors.background,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor:
            isDark ? AppColors.darkBackground : AppColors.mist,
        surfaceTintColor: Colors.transparent,
        foregroundColor: textColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 4,
        titleTextStyle:
            style(size: 22, weight: FontWeight.w800),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(
              color: isDark
                  ? AppColors.darkDivider
                  : AppColors.border),
        ),
      ),
      listTileTheme: ListTileThemeData(
        dense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        titleTextStyle: style(size: 13.5, weight: FontWeight.w600),
        subtitleTextStyle:
            style(size: 12, weight: FontWeight.w400, color: secondary),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: isDark
            ? AppColors.darkBackground
            : AppColors.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(
              color: isDark
                  ? AppColors.darkDivider
                  : AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(
              color: isDark
                  ? AppColors.darkDivider
                  : AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide:
              const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        labelStyle:
            style(size: 12, weight: FontWeight.w400, color: secondary),
        hintStyle:
            style(size: 12, weight: FontWeight.w400, color: secondary),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          textStyle: style(
              size: 13, weight: FontWeight.w700, color: Colors.white),
          minimumSize: const Size(0, 50),
          padding:
              const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          textStyle: style(size: 13, weight: FontWeight.w600),
          minimumSize: const Size(0, 50),
          side: BorderSide(
              color: isDark
                  ? AppColors.darkDivider
                  : const Color(0xFFD6DAEA),
              width: 1.5),
          padding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: style(size: 13, weight: FontWeight.w700),
          foregroundColor: isDark ? AppColors.darkPrimary : AppColors.indigoDeep,
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
      ),
      chipTheme: scheme.brightness == Brightness.dark
          ? null
          : ChipThemeData(
              backgroundColor: AppColors.neutralContainer,
              side: BorderSide.none,
              labelStyle: style(size: 11.5, weight: FontWeight.w700),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999)),
            ),
      tabBarTheme: TabBarThemeData(
        labelStyle: style(size: 13, weight: FontWeight.w700),
        unselectedLabelStyle:
            style(size: 13, weight: FontWeight.w400, color: secondary),
      ),
      dividerTheme: DividerThemeData(
        color:
            isDark ? AppColors.darkDivider : AppColors.divider,
        thickness: 1,
        space: 1,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: scheme.surface,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: secondary,
        selectedLabelStyle:
            style(size: 11, weight: FontWeight.w600),
        unselectedLabelStyle:
            style(size: 11, weight: FontWeight.w400, color: secondary),
        type: BottomNavigationBarType.fixed,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surface,
        selectedIconTheme:
            const IconThemeData(color: AppColors.primary),
        unselectedIconTheme: IconThemeData(color: secondary),
        selectedLabelTextStyle:
            style(size: 11.5, weight: FontWeight.w700),
        unselectedLabelTextStyle:
            style(size: 11.5, weight: FontWeight.w400, color: secondary),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: AppColors.primaryContainer,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStatePropertyAll(
            style(size: 11, weight: FontWeight.w600)),
      ),
      drawerTheme: DrawerThemeData(backgroundColor: scheme.surface),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.ink,
        contentTextStyle:
            style(size: 13, weight: FontWeight.w600, color: Colors.white),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.xl)),
      ),
    );
  }
}
