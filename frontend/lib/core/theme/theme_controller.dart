import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _themeModeStorageKey = 'mushukistan_theme_mode';

enum AppThemeMode {
  original,
  light,
  dark,
}

final appThemeModeProvider = StateProvider<AppThemeMode>((ref) {
  return AppThemeMode.original;
});

Future<AppThemeMode> loadSavedThemeMode() async {
  const storage = FlutterSecureStorage();
  try {
    final saved = await storage.read(key: _themeModeStorageKey);
    return AppThemeMode.values.firstWhere(
      (mode) => mode.name == saved,
      orElse: () => AppThemeMode.original,
    );
  } catch (_) {
    return AppThemeMode.original;
  }
}

Future<void> saveThemeMode(AppThemeMode mode) async {
  const storage = FlutterSecureStorage();
  try {
    await storage.write(key: _themeModeStorageKey, value: mode.name);
  } catch (_) {
    // The selected mode still applies for this session if storage is unavailable.
  }
}

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
