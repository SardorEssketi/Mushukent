import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _languageStorageKey = 'mushukistan_app_language';

enum AppLanguage {
  english('en', 'English'),
  uzbek('uz', 'Uzbek'),
  russian('ru', 'Russian');

  const AppLanguage(this.code, this.label);

  final String code;
  final String label;

  Locale get locale => Locale(code);

  static AppLanguage fromCode(String? code) {
    return switch (code) {
      'uz' => AppLanguage.uzbek,
      'ru' => AppLanguage.russian,
      _ => AppLanguage.english,
    };
  }
}

final appLanguageProvider = StateProvider<AppLanguage>((ref) {
  return AppLanguage.english;
});

/// The last language the app used on this device. The account's `preferred_language` is only known
/// after the server confirms the session, so without a local copy a Russian or Uzbek user would see
/// English screens during an outage or a cold start.
Future<AppLanguage?> loadSavedLanguage() async {
  const storage = FlutterSecureStorage();
  try {
    final saved = await storage.read(key: _languageStorageKey);
    if (saved == null) return null;
    return AppLanguage.fromCode(saved);
  } catch (_) {
    return null;
  }
}

Future<void> saveLanguage(AppLanguage language) async {
  const storage = FlutterSecureStorage();
  try {
    await storage.write(key: _languageStorageKey, value: language.code);
  } catch (_) {
    // The language still applies for this session if storage is unavailable.
  }
}
