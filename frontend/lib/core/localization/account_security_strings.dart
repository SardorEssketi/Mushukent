import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'language_controller.dart';

final accountSecurityStringsProvider = Provider<AccountSecurityStrings>((ref) {
  return AccountSecurityStrings.forLanguage(ref.watch(appLanguageProvider));
});

class AccountSecurityStrings {
  const AccountSecurityStrings({
    required this.title,
    required this.signInMethods,
    required this.connected,
    required this.notConnected,
    required this.passwordSet,
    required this.passwordNotSet,
    required this.setPassword,
    required this.changePassword,
    required this.connectGoogle,
    required this.separatePassword,
    required this.currentPassword,
    required this.newPassword,
    required this.confirmPassword,
    required this.passwordLength,
    required this.passwordMismatch,
    required this.required,
    required this.save,
    required this.saved,
    required this.connectionSaved,
    required this.loadFailed,
    required this.googleFailed,
    required this.google,
    required this.password,
    required this.loginHelp,
  });

  final String title;
  final String signInMethods;
  final String connected;
  final String notConnected;
  final String passwordSet;
  final String passwordNotSet;
  final String setPassword;
  final String changePassword;
  final String connectGoogle;
  final String separatePassword;
  final String currentPassword;
  final String newPassword;
  final String confirmPassword;
  final String passwordLength;
  final String passwordMismatch;
  final String required;
  final String save;
  final String saved;
  final String connectionSaved;
  final String loadFailed;
  final String googleFailed;
  final String google;
  final String password;
  final String loginHelp;

  static AccountSecurityStrings forLanguage(AppLanguage language) =>
      switch (language) {
        AppLanguage.english => const AccountSecurityStrings(
            title: 'Account Security',
            signInMethods: 'Sign-in methods',
            connected: 'Connected',
            notConnected: 'Not connected',
            passwordSet: 'Set',
            passwordNotSet: 'Not set',
            setPassword: 'Set password',
            changePassword: 'Change password',
            connectGoogle: 'Connect Google',
            separatePassword:
                'Create a password for your Mushukistan account. This is separate from your Google password.',
            currentPassword: 'Current password',
            newPassword: 'New password',
            confirmPassword: 'Confirm new password',
            passwordLength: 'Use 8 to 128 characters.',
            passwordMismatch: 'Passwords do not match.',
            required: 'Required',
            save: 'Save password',
            saved: 'Password saved.',
            connectionSaved: 'Google connected.',
            loadFailed: 'Could not load sign-in methods.',
            googleFailed: 'Could not connect Google. Please try again.',
            google: 'Google',
            password: 'Password',
            loginHelp:
                'If you signed up with Google, use Continue with Google. You can set a separate Mushukistan password in Account Security after signing in.'),
        AppLanguage.uzbek => const AccountSecurityStrings(
            title: 'Hisob xavfsizligi',
            signInMethods: 'Kirish usullari',
            connected: 'Ulangan',
            notConnected: 'Ulanmagan',
            passwordSet: 'O‘rnatilgan',
            passwordNotSet: 'O‘rnatilmagan',
            setPassword: 'Parol o‘rnatish',
            changePassword: 'Parolni o‘zgartirish',
            connectGoogle: 'Google hisobini ulash',
            separatePassword:
                'Mushukistan hisobingiz uchun parol yarating. Bu Google parolingizdan alohida.',
            currentPassword: 'Joriy parol',
            newPassword: 'Yangi parol',
            confirmPassword: 'Yangi parolni tasdiqlang',
            passwordLength: '8 dan 128 tagacha belgi kiriting.',
            passwordMismatch: 'Parollar mos kelmadi.',
            required: 'Majburiy',
            save: 'Parolni saqlash',
            saved: 'Parol saqlandi.',
            connectionSaved: 'Google ulandi.',
            loadFailed: 'Kirish usullarini yuklab bo‘lmadi.',
            googleFailed:
                'Google hisobini ulab bo‘lmadi. Qayta urinib ko‘ring.',
            google: 'Google',
            password: 'Parol',
            loginHelp:
                'Agar Google orqali ro‘yxatdan o‘tgan bo‘lsangiz, Google bilan davom eting. Kirgach, Hisob xavfsizligida alohida Mushukistan parolini o‘rnatishingiz mumkin.'),
        AppLanguage.russian => const AccountSecurityStrings(
            title: 'Безопасность аккаунта',
            signInMethods: 'Способы входа',
            connected: 'Подключён',
            notConnected: 'Не подключён',
            passwordSet: 'Установлен',
            passwordNotSet: 'Не установлен',
            setPassword: 'Установить пароль',
            changePassword: 'Изменить пароль',
            connectGoogle: 'Подключить Google',
            separatePassword:
                'Создайте пароль для аккаунта Mushukistan. Он не связан с вашим паролем Google.',
            currentPassword: 'Текущий пароль',
            newPassword: 'Новый пароль',
            confirmPassword: 'Подтвердите новый пароль',
            passwordLength: 'Используйте от 8 до 128 символов.',
            passwordMismatch: 'Пароли не совпадают.',
            required: 'Обязательно',
            save: 'Сохранить пароль',
            saved: 'Пароль сохранён.',
            connectionSaved: 'Google подключён.',
            loadFailed: 'Не удалось загрузить способы входа.',
            googleFailed: 'Не удалось подключить Google. Попробуйте ещё раз.',
            google: 'Google',
            password: 'Пароль',
            loginHelp:
                'Если вы зарегистрировались через Google, войдите с помощью Google. Затем в разделе безопасности аккаунта можно установить отдельный пароль Mushukistan.'),
      };
}
