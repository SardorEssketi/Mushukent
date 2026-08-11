import 'package:flutter/material.dart';

import 'app_design_tokens.dart';

class AppTheme {
  static ThemeData get light {
    const colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: AppPalette.terracotta,
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFFFDAD0),
      onPrimaryContainer: AppPalette.terracottaDark,
      secondary: AppPalette.sage,
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
          borderRadius: BorderRadius.circular(AppRadii.lg),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          borderSide:
              const BorderSide(color: AppPalette.terracotta, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: colorScheme.primary,
          side: BorderSide(color: colorScheme.outlineVariant),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colorScheme.primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
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
        indicatorColor: colorScheme.primaryContainer,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight:
                states.contains(WidgetState.selected) ? FontWeight.w800 : null,
          ),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadii.xl),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
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
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
          color: AppPalette.graphite,
        ),
        titleLarge: TextStyle(
          fontWeight: FontWeight.w800,
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
        labelLarge: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0),
      ),
    );
  }

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppPalette.terracotta,
          brightness: Brightness.dark,
        ),
      );
}
