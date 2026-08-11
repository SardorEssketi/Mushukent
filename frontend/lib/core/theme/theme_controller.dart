import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AppThemeMode {
  original,
  light,
  dark,
}

final appThemeModeProvider = StateProvider<AppThemeMode>((ref) {
  return AppThemeMode.original;
});

extension AppThemeModeThemeMode on AppThemeMode {
  ThemeMode get themeMode {
    switch (this) {
      case AppThemeMode.original:
        return ThemeMode.system;
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.dark:
        return ThemeMode.dark;
    }
  }
}
