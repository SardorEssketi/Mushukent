import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/lifecycle/app_resume.dart';
import 'core/localization/l10n.dart';
import 'core/localization/language_controller.dart';
import 'core/routing/app_router.dart';
import 'core/startup/startup_log.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'features/auth/application/auth_controller.dart';
import 'features/notifications/application/notification_push.dart';

class MushukistanApp extends ConsumerStatefulWidget {
  const MushukistanApp({super.key});

  @override
  ConsumerState<MushukistanApp> createState() => _MushukistanAppState();
}

class _MushukistanAppState extends ConsumerState<MushukistanApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    logStartupStage('Flutter application mounted');
    unawaited(
      loadSavedThemeMode().then((mode) {
        if (mounted) {
          ref.read(appThemeModeProvider.notifier).state = mode;
        }
      }),
    );
    unawaited(
      loadSavedLanguage().then((saved) {
        // A language chosen by the signed-in account (applied below) wins over the stored one.
        if (saved != null &&
            mounted &&
            ref.read(authControllerProvider).user == null) {
          ref.read(appLanguageProvider.notifier).state = saved;
        }
      }),
    );
    ref.listenManual<AppResume?>(appResumeProvider, (previous, next) {
      // Back after a long time away: quietly confirm a signed-in session is still valid.
      if (next != null && next.sessionIsStale) {
        unawaited(
            ref.read(authControllerProvider.notifier).revalidateSession());
      }
    });
    ref.listenManual<AppLanguage>(
      appLanguageProvider,
      (previous, next) {
        if (previous != next) unawaited(saveLanguage(next));
      },
    );
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
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back in the foreground (tab visible again, app resumed): the network may be back, so
    // re-check a stored session that could not be confirmed. No-op in every other state.
    // One place turns lifecycle changes into "back after N minutes" events for the screens.
    ref.read(appResumeProvider.notifier).handleLifecycle(state);
    if (state == AppLifecycleState.resumed) {
      unawaited(ref.read(authControllerProvider.notifier).retrySession());
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(appThemeModeProvider);
    final language = ref.watch(appLanguageProvider);

    return NotificationLifecycle(
      router: router,
      child: MaterialApp.router(
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
      ),
    );
  }
}
