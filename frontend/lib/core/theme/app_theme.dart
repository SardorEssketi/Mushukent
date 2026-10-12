import 'package:flutter/material.dart';

import 'app_design_tokens.dart';

class AppTheme {
  static const fontFamily = 'Manrope';

  static ThemeData get light => _build(_lightScheme);
  static ThemeData get dark => _build(_darkScheme);

  static const _lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: AppPalette.terracottaDark,
    onPrimary: Colors.white,
    primaryContainer: Color(0xFFFFE3D9),
    onPrimaryContainer: Color(0xFF6E2410),
    secondary: AppPalette.sageDark,
    onSecondary: Colors.white,
    secondaryContainer: Color(0xFFD7EFE8),
    onSecondaryContainer: Color(0xFF0E3D33),
    tertiary: AppPalette.adoption,
    onTertiary: Colors.white,
    tertiaryContainer: Color(0xFFFFEBCB),
    onTertiaryContainer: Color(0xFF4F3109),
    error: AppPalette.lost,
    onError: Colors.white,
    errorContainer: Color(0xFFFFDAD8),
    onErrorContainer: Color(0xFF780F1A),
    surface: AppPalette.surface,
    onSurface: AppPalette.graphite,
    surfaceContainerLowest: AppPalette.cream,
    surfaceContainerLow: AppPalette.warmSurface,
    surfaceContainer: Color(0xFFF6EFE8),
    surfaceContainerHigh: Color(0xFFF0E7DE),
    surfaceContainerHighest: Color(0xFFE9DED3),
    onSurfaceVariant: AppPalette.graphiteMuted,
    outline: Color(0xFF8A7F76),
    outlineVariant: AppPalette.line,
    shadow: Color(0xFF4A2A1A),
    scrim: Color(0x66000000),
    inverseSurface: Color(0xFF3A322D),
    onInverseSurface: Color(0xFFF8EEE6),
    inversePrimary: Color(0xFFFFB5A0),
  );

  static const _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFFFB59E),
    onPrimary: Color(0xFF55200E),
    primaryContainer: Color(0xFF7A2E18),
    onPrimaryContainer: Color(0xFFFFDBCF),
    secondary: Color(0xFF9AD4C4),
    onSecondary: Color(0xFF0B3A30),
    secondaryContainer: Color(0xFF225246),
    onSecondaryContainer: Color(0xFFB7F0E0),
    tertiary: Color(0xFFE7C69B),
    onTertiary: Color(0xFF493314),
    tertiaryContainer: Color(0xFF614820),
    onTertiaryContainer: Color(0xFFFFDEB1),
    error: Color(0xFFFFB3B0),
    onError: Color(0xFF68000F),
    errorContainer: Color(0xFF93001B),
    onErrorContainer: Color(0xFFFFDAD8),
    surface: Color(0xFF211C19),
    onSurface: Color(0xFFF0E3DB),
    surfaceContainerLowest: Color(0xFF171210),
    surfaceContainerLow: Color(0xFF1C1714),
    surfaceContainer: Color(0xFF2A2420),
    surfaceContainerHigh: Color(0xFF352E29),
    surfaceContainerHighest: Color(0xFF403832),
    onSurfaceVariant: Color(0xFFD8C6BB),
    outline: Color(0xFFA18F85),
    outlineVariant: Color(0xFF4E433C),
    shadow: Color(0xFF000000),
    scrim: Color(0x99000000),
    inverseSurface: Color(0xFFF0E3DB),
    onInverseSurface: Color(0xFF211C19),
    inversePrimary: AppPalette.terracottaDark,
  );

  /// Type scale: display, title, body, caption with two working weights
  /// (w500 body, w700/w800 emphasis).
  static TextTheme _textTheme(ColorScheme c) {
    TextStyle s(double size, FontWeight w, {double h = 1.35, Color? color}) =>
        TextStyle(
          fontFamily: fontFamily,
          fontSize: size,
          fontWeight: w,
          height: h,
          letterSpacing: 0,
          color: color ?? c.onSurface,
        );
    return TextTheme(
      displaySmall: s(32, FontWeight.w800, h: 1.15),
      headlineMedium: s(28, FontWeight.w800, h: 1.2),
      headlineSmall: s(24, FontWeight.w800, h: 1.25),
      titleLarge: s(20, FontWeight.w700, h: 1.3),
      titleMedium: s(16, FontWeight.w700),
      titleSmall: s(14, FontWeight.w700),
      bodyLarge: s(16, FontWeight.w500, h: 1.5),
      bodyMedium: s(14, FontWeight.w500, h: 1.45),
      bodySmall: s(12, FontWeight.w500, color: c.onSurfaceVariant),
      labelLarge: s(14, FontWeight.w700),
      labelMedium: s(12, FontWeight.w700),
      labelSmall: s(11, FontWeight.w700, color: c.onSurfaceVariant),
    );
  }

  static ThemeData _build(ColorScheme c) {
    final isDark = c.brightness == Brightness.dark;
    final text = _textTheme(c);
    final controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadii.control),
    );
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
          borderSide: BorderSide(color: color, width: width),
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: c,
      fontFamily: fontFamily,
      textTheme: text,
      scaffoldBackgroundColor: c.surfaceContainerLowest,
      visualDensity: VisualDensity.standard,
      appBarTheme: AppBarTheme(
        backgroundColor: c.surfaceContainerLowest,
        foregroundColor: c.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: text.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
          side: BorderSide(color: c.outlineVariant),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? c.surfaceContainer : c.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: border(c.outlineVariant),
        enabledBorder: border(c.outlineVariant),
        disabledBorder: border(c.outlineVariant.withValues(alpha: 0.5)),
        focusedBorder: border(c.primary, 2),
        errorBorder: border(c.error),
        focusedErrorBorder: border(c.error, 2),
        labelStyle: text.bodyMedium?.copyWith(color: c.onSurfaceVariant),
        hintStyle: text.bodyMedium?.copyWith(
          color: c.onSurfaceVariant.withValues(alpha: 0.8),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 52),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          textStyle: text.labelLarge,
          shape: const StadiumBorder(),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(48, 52),
          textStyle: text.labelLarge,
          shape: const StadiumBorder(),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 52),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          textStyle: text.labelLarge,
          foregroundColor: c.onSurface,
          side: BorderSide(color: c.outline.withValues(alpha: 0.5)),
          shape: const StadiumBorder(),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.primary,
          minimumSize: const Size(48, 48),
          textStyle: text.labelLarge,
          shape: const StadiumBorder(),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: c.onSurfaceVariant,
          minimumSize: const Size(48, 48),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide(color: c.outlineVariant),
        labelStyle: text.labelMedium,
        backgroundColor: c.surface,
        selectedColor: c.primaryContainer,
        checkmarkColor: c.onPrimaryContainer,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          shape: const StadiumBorder(),
          textStyle: text.labelLarge,
          backgroundColor: c.surface,
          foregroundColor: c.onSurface,
          selectedBackgroundColor: c.primaryContainer,
          selectedForegroundColor: c.onPrimaryContainer,
          side: BorderSide(color: c.outlineVariant),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: c.primary,
        foregroundColor: c.onPrimary,
        elevation: 2,
        shape: controlShape,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 68,
        indicatorColor: c.primaryContainer,
        indicatorShape: const StadiumBorder(),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => text.labelMedium?.copyWith(
            color: states.contains(WidgetState.selected)
                ? c.onSurface
                : c.onSurfaceVariant,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 24,
            color: states.contains(WidgetState.selected)
                ? c.onPrimaryContainer
                : c.onSurfaceVariant,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: c.surface,
        indicatorColor: c.primaryContainer,
        indicatorShape: const StadiumBorder(),
        selectedLabelTextStyle: text.labelMedium?.copyWith(color: c.onSurface),
        unselectedLabelTextStyle: text.labelMedium,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadii.sheet),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: text.titleLarge,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.dialog),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.inverseSurface,
        contentTextStyle: text.bodyMedium?.copyWith(color: c.onInverseSurface),
        behavior: SnackBarBehavior.floating,
        shape: controlShape,
      ),
      listTileTheme: ListTileThemeData(
        shape: controlShape,
        iconColor: c.onSurfaceVariant,
      ),
      dividerTheme: DividerThemeData(color: c.outlineVariant, thickness: 1),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: c.primary),
      focusColor: c.primary.withValues(alpha: 0.16),
    );
  }
}
