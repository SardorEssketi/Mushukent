import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/localization/l10n.dart';
import 'core/localization/language_controller.dart';
import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'features/auth/application/auth_controller.dart';

class MushukistanApp extends ConsumerStatefulWidget {
  const MushukistanApp({super.key});

  @override
  ConsumerState<MushukistanApp> createState() => _MushukistanAppState();
}

class _MushukistanAppState extends ConsumerState<MushukistanApp> {
  @override
  void initState() {
    super.initState();
    ref.listenManual<String?>(
      authControllerProvider.select((state) => state.user?.preferredLanguage),
      (previous, next) {
        if (next == null || next == previous) {
          return;
        }
        ref.read(appLanguageProvider.notifier).state =
            AppLanguage.fromCode(next);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(appThemeModeProvider);
    final language = ref.watch(appLanguageProvider);

    return MaterialApp.router(
      title: 'Mushukistan',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode.themeMode,
      locale: language.locale,
      routerConfig: router,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: L10n.supportedLocales,
    );
  }
}
