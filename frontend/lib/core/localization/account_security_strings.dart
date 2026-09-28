import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'language_controller.dart';

final accountSecurityStringsProvider = Provider<AccountSecurityStrings>((ref) {
  return AccountSecurityStrings.forLanguage(ref.watch(appLanguageProvider));
});

class AccountSecurityStrings {
  const AccountSecurityStrings({
    required this.title,
    required this.passwordSet,
    required this.changePassword,
    required this.currentPassword,
    required this.newPassword,
    required this.confirmPassword,
    required this.passwordLength,
    required this.passwordMismatch,
    required this.required,
    required this.save,
    required this.saved,
    required this.loadFailed,
    required this.password,
    required this.emailAddress,
    required this.emailUnavailable,
    required this.emailVerified,
    required this.emailNeedsVerification,
  });

  final String title;
  final String passwordSet;
  final String changePassword;
  final String currentPassword;
  final String newPassword;
  final String confirmPassword;
  final String passwordLength;
  final String passwordMismatch;
  final String required;
  final String save;
  final String saved;
  final String loadFailed;
  final String password;
  final String emailAddress;
  final String emailUnavailable;
  final String emailVerified;
  final String emailNeedsVerification;

  static AccountSecurityStrings forLanguage(AppLanguage language) =>
      switch (language) {
        AppLanguage.english => const AccountSecurityStrings(
            title: 'Security',
            passwordSet: 'Enabled',
            changePassword: 'Change password',
            currentPassword: 'Current password',
            newPassword: 'New password',
            confirmPassword: 'Confirm new password',
            passwordLength: 'Use 8 to 128 characters.',
            passwordMismatch: 'Passwords do not match.',
            required: 'Required',
            save: 'Save password',
            saved: 'Password saved.',
            loadFailed: 'Could not load account security settings.',
            password: 'Password',
            emailAddress: 'Email',
            emailUnavailable: 'Email address unavailable',
            emailVerified: 'Verified',
            emailNeedsVerification: 'Needs verification',
          ),
        AppLanguage.uzbek => const AccountSecurityStrings(
            title: 'Xavfsizlik',
            passwordSet: 'Yoqilgan',
            changePassword: 'Parolni o‘zgartirish',
            currentPassword: 'Joriy parol',
            newPassword: 'Yangi parol',
            confirmPassword: 'Yangi parolni tasdiqlang',
            passwordLength: '8 dan 128 tagacha belgi kiriting.',
            passwordMismatch: 'Parollar mos kelmadi.',
            required: 'Majburiy',
            save: 'Parolni saqlash',
            saved: 'Parol saqlandi.',
            loadFailed: 'Hisob xavfsizligi sozlamalarini yuklab bo‘lmadi.',
            password: 'Parol',
            emailAddress: 'Elektron pochta',
            emailUnavailable: 'Elektron pochta manzili mavjud emas',
            emailVerified: 'Tasdiqlangan',
            emailNeedsVerification: 'Tasdiqlash kerak',
          ),
        AppLanguage.russian => const AccountSecurityStrings(
            title: 'Безопасность',
            passwordSet: 'Включён',
            changePassword: 'Изменить пароль',
            currentPassword: 'Текущий пароль',
            newPassword: 'Новый пароль',
            confirmPassword: 'Подтвердите новый пароль',
            passwordLength: 'Используйте от 8 до 128 символов.',
            passwordMismatch: 'Пароли не совпадают.',
            required: 'Обязательное поле',
            save: 'Сохранить пароль',
            saved: 'Пароль сохранён.',
            loadFailed: 'Не удалось загрузить настройки безопасности.',
            password: 'Пароль',
            emailAddress: 'Электронная почта',
            emailUnavailable: 'Адрес электронной почты недоступен',
            emailVerified: 'Подтверждён',
            emailNeedsVerification: 'Требуется подтверждение',
          ),
      };
}
