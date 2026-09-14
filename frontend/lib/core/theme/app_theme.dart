import 'package:flutter/material.dart';

import 'app_design_tokens.dart';

class AppTheme {
  static ThemeData get light {
    const colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: AppPalette.terracottaDark,
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFFFDAD0),
      onPrimaryContainer: AppPalette.terracottaDark,
      secondary: AppPalette.sageDark,
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFFDCEAD8),
      onSecondaryContainer: AppPalette.sageDark,
      tertiary: AppPalette.adoption,
      onTertiary: Colors.white,
      tertiaryContainer: Color(0xFFFFE4C3),
      onTertiaryContainer: Color(0xFF5E4224),
      error: AppPalette.lost,
      onError: Colors.white,
      errorContainer: Color(0xFFFFDAD5),
      onErrorContainer: Color(0xFF7A231C),
      surface: AppPalette.surface,
      onSurface: AppPalette.graphite,
      surfaceContainerLowest: AppPalette.cream,
      surfaceContainerLow: AppPalette.warmSurface,
      surfaceContainer: Color(0xFFF8F0E8),
      surfaceContainerHigh: Color(0xFFF2E8DE),
      surfaceContainerHighest: Color(0xFFECE0D6),
      onSurfaceVariant: AppPalette.graphiteMuted,
      outline: Color(0xFF8C7E74),
      outlineVariant: AppPalette.line,
      shadow: Color(0x33000000),
      scrim: Color(0x66000000),
      inverseSurface: Color(0xFF403A36),
      onInverseSurface: Color(0xFFF8EEE6),
      inversePrimary: Color(0xFFFFB5A3),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surfaceContainerLowest,
      fontFamily: 'Roboto',
      appBarTheme: const AppBarTheme(
        backgroundColor: AppPalette.cream,
        foregroundColor: AppPalette.graphite,
        elevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
          borderSide:
              const BorderSide(color: AppPalette.terracotta, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.control),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: colorScheme.primary,
          side: BorderSide(color: colorScheme.outlineVariant),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.control),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colorScheme.primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.control),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: colorScheme.onSurfaceVariant,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surface,
        indicatorColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight:
                states.contains(WidgetState.selected) ? FontWeight.w600 : null,
          ),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadii.sheet),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.dialog),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle: TextStyle(color: colorScheme.onInverseSurface),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant,
        thickness: 1,
      ),
      textTheme: const TextTheme(
        headlineSmall: TextStyle(
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
          color: AppPalette.graphite,
        ),
        titleLarge: TextStyle(
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
          color: AppPalette.graphite,
        ),
        titleMedium: TextStyle(
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
          color: AppPalette.graphite,
        ),
        bodyLarge: TextStyle(letterSpacing: 0, color: AppPalette.graphite),
        bodyMedium: TextStyle(letterSpacing: 0, color: AppPalette.graphite),
        bodySmall: TextStyle(letterSpacing: 0, color: AppPalette.graphiteMuted),
        labelLarge: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0),
      ),
    );
  }

  static ThemeData get dark {
    const colorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xFFFFB5A3),
      onPrimary: Color(0xFF5B1F16),
      primaryContainer: Color(0xFF7A2E20),
      onPrimaryContainer: Color(0xFFFFDAD0),
      secondary: Color(0xFFAEC9AE),
      onSecondary: Color(0xFF203D26),
      secondaryContainer: Color(0xFF38563C),
      onSecondaryContainer: Color(0xFFC9E6C8),
      tertiary: Color(0xFFE7C69B),
      onTertiary: Color(0xFF493314),
      tertiaryContainer: Color(0xFF614820),
      onTertiaryContainer: Color(0xFFFFDEB1),
      error: Color(0xFFFFB4AB),
      onError: Color(0xFF690005),
      errorContainer: Color(0xFF93000A),
      onErrorContainer: Color(0xFFFFDAD6),
      surface: Color(0xFF211C19),
      onSurface: Color(0xFFEFE0D8),
      surfaceContainerLowest: Color(0xFF17120F),
      surfaceContainerLow: Color(0xFF27211E),
      surfaceContainer: Color(0xFF2D2622),
      surfaceContainerHigh: Color(0xFF38302C),
      surfaceContainerHighest: Color(0xFF433A35),
      onSurfaceVariant: Color(0xFFD8C3B9),
      outline: Color(0xFFA18C83),
      outlineVariant: Color(0xFF544740),
      shadow: Color(0x66000000),
      scrim: Color(0x99000000),
      inverseSurface: Color(0xFFEFE0D8),
      onInverseSurface: Color(0xFF211C19),
      inversePrimary: AppPalette.terracottaDark,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surfaceContainerLowest,
      fontFamily: 'Roboto',
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF17120F),
        foregroundColor: Color(0xFFEFE0D8),
        elevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.control),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: colorScheme.primary,
          side: BorderSide(color: colorScheme.outlineVariant),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.control),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colorScheme.primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.control),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surface,
        indicatorColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : null,
          ),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadii.sheet),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.dialog),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant,
        thickness: 1,
      ),
      textTheme: const TextTheme(
        headlineSmall: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0),
        titleLarge: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0),
        titleMedium: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0),
        bodyLarge: TextStyle(letterSpacing: 0),
        bodyMedium: TextStyle(letterSpacing: 0),
        bodySmall: TextStyle(letterSpacing: 0),
        labelLarge: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0),
      ),
    );
  }
}
