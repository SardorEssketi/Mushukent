import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
