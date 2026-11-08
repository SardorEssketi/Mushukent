// EMU-107: backing out of the Google sheet is not an error. Login shows no
// raw SDK text ("[16] Cancelled by user."), keeps what was typed and creates
// no session; real failures get a localized message.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mushukistan_frontend/core/localization/language_controller.dart';
import 'package:mushukistan_frontend/core/network/api_error.dart';
import 'package:mushukistan_frontend/features/auth/application/auth_controller.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_models.dart';
import 'package:mushukistan_frontend/features/auth/infrastructure/google_sign_in_service.dart';
import 'package:mushukistan_frontend/features/auth/presentation/screens/login_screen.dart';

import '../../support/fakes.dart';

const _rawCancel = '[16] Cancelled by user.';

GoogleSignInFlowException _flow(GoogleSignInFailure failure,
        [String message = _rawCancel]) =>
    GoogleSignInFlowException(message, failure: failure);

/// Answers each authenticate() call with the next scripted outcome.
class _ScriptedGoogle implements GoogleIdentityTokenProvider {
  _ScriptedGoogle(this.outcomes);
  final List<Object> outcomes;
  int calls = 0;

  @override
  Future<String> authenticate() async {
    final outcome =
        outcomes[calls < outcomes.length ? calls : outcomes.length - 1];
    calls++;
    if (outcome is String) return outcome;
    throw outcome;
  }
}

AuthSession _session() => AuthSession(accessToken: 'token', user: testUser());

void main() {
  group('plugin error codes', () {
    test('map to cancellation, configuration, availability or failure', () {
      expect(googleSignInFailureFor(GoogleSignInExceptionCode.canceled),
          GoogleSignInFailure.cancelled);
      expect(
          googleSignInFailureFor(
              GoogleSignInExceptionCode.clientConfigurationError),
          GoogleSignInFailure.notConfigured);
      expect(
          googleSignInFailureFor(
              GoogleSignInExceptionCode.providerConfigurationError),
          GoogleSignInFailure.notConfigured);
      expect(googleSignInFailureFor(GoogleSignInExceptionCode.uiUnavailable),
          GoogleSignInFailure.unavailable);
      for (final code in [
        GoogleSignInExceptionCode.interrupted,
        GoogleSignInExceptionCode.userMismatch,
        GoogleSignInExceptionCode.unknownError,
      ]) {
        expect(googleSignInFailureFor(code), GoogleSignInFailure.failed,
            reason: '$code');
      }
    });
  });

  group('AuthController.loginWithGoogle', () {
    Future<(ProviderContainer, FakeAuthRepository)> controller(
        GoogleIdentityTokenProvider google) async {
      final repository = FakeAuthRepository()..loginResult = _session();
      final container = ProviderContainer(overrides: [
        authRepositoryProvider.overrideWithValue(repository),
        googleIdentityTokenProvider.overrideWithValue(google),
      ]);
      addTearDown(container.dispose);
      await container.read(authControllerProvider.notifier).restoreSession();
      return (container, repository);
    }

    test('cancellation: no error, no message, no session, no backend call',
        () async {
      final google = _ScriptedGoogle([_flow(GoogleSignInFailure.cancelled)]);
      final (container, repository) = await controller(google);
      await container.read(authControllerProvider.notifier).loginWithGoogle();
      final state = container.read(authControllerProvider);
      expect(state.isAuthenticated, isFalse);
      expect(state.hasError, isFalse);
      expect(state.message, isNull);
      expect(repository.lastGoogleIdToken, isNull);
    });

    test('repeated cancellation stays quiet and clears an older error',
        () async {
      final google = _ScriptedGoogle([
        _flow(GoogleSignInFailure.failed, 'Something broke'),
        _flow(GoogleSignInFailure.cancelled),
        _flow(GoogleSignInFailure.cancelled),
      ]);
      final (container, _) = await controller(google);
      final notifier = container.read(authControllerProvider.notifier);
      await expectLater(notifier.loginWithGoogle(),
          throwsA(isA<GoogleSignInFlowException>()));
      expect(container.read(authControllerProvider).hasError, isTrue);
      await notifier.loginWithGoogle();
      expect(container.read(authControllerProvider).hasError, isFalse);
      await notifier.loginWithGoogle();
      expect(container.read(authControllerProvider).hasError, isFalse);
      expect(google.calls, 3);
    });

    test('success still signs in', () async {
      final google = _ScriptedGoogle(['google-id-token']);
      final (container, repository) = await controller(google);
      await container.read(authControllerProvider.notifier).loginWithGoogle();
      expect(container.read(authControllerProvider).isAuthenticated, isTrue);
      expect(repository.lastGoogleIdToken, 'google-id-token');
    });

    test('real failures show a described message, never the raw SDK text',
        () async {
      for (final (failure, expected) in [
        (GoogleSignInFailure.notConfigured, 'not configured'),
        (GoogleSignInFailure.unavailable, 'unavailable'),
        (GoogleSignInFailure.failed, 'failed'),
      ]) {
        final google = _ScriptedGoogle([_flow(failure)]);
        final (container, _) = await controller(google);
        await expectLater(
          container.read(authControllerProvider.notifier).loginWithGoogle(
                describeFailure: (f) => switch (f) {
                  GoogleSignInFailure.notConfigured => 'not configured',
                  GoogleSignInFailure.unavailable => 'unavailable',
                  _ => 'failed',
                },
              ),
          throwsA(isA<GoogleSignInFlowException>()),
        );
        final state = container.read(authControllerProvider);
        expect(state.message, expected, reason: '$failure');
        expect(state.isAuthenticated, isFalse);
      }
    });

    test('without a describer, a neutral default replaces the raw text',
        () async {
      final google = _ScriptedGoogle([_flow(GoogleSignInFailure.failed)]);
      final (container, _) = await controller(google);
      await expectLater(
          container.read(authControllerProvider.notifier).loginWithGoogle(),
          throwsA(isA<GoogleSignInFlowException>()));
      final message = container.read(authControllerProvider).message!;
      expect(message, isNot(contains('[16]')));
      expect(message, isNot(contains('Cancelled by user')));
    });

    test('a network failure exchanging the token is still reported', () async {
      final google = _ScriptedGoogle(['google-id-token']);
      final (container, repository) = await controller(google);
      repository.loginError = const MushukistanApiException(
          kind: ApiFailureKind.network,
          code: 'NETWORK_ERROR',
          message: 'No connection.');
      await expectLater(
          container.read(authControllerProvider.notifier).loginWithGoogle(),
          throwsA(isA<MushukistanApiException>()));
      final state = container.read(authControllerProvider);
      expect(state.isAuthenticated, isFalse);
      expect(state.hasError, isTrue);
    });
  });

  group('Login screen', () {
    Future<GoRouter> mountLogin(
      WidgetTester tester,
      GoogleIdentityTokenProvider google, {
      AppLanguage language = AppLanguage.english,
      ProviderContainer? container,
    }) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final scope = container ??
          ProviderContainer(overrides: [
            authRepositoryProvider.overrideWithValue(
                FakeAuthRepository()..loginResult = _session()),
            googleIdentityTokenProvider.overrideWithValue(google),
            appLanguageProvider.overrideWith((ref) => language),
          ]);
      if (container == null) addTearDown(scope.dispose);
      final router = GoRouter(initialLocation: '/login', routes: [
        GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
        GoRoute(
            path: '/:rest(.*)',
            builder: (_, __) => const Scaffold(body: Text('Elsewhere'))),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: scope,
        child: MaterialApp.router(routerConfig: router),
      ));
      await tester.pumpAndSettle();
      return router;
    }

    testWidgets('cancel keeps a usable Login with the typed email',
        (tester) async {
      final google = _ScriptedGoogle([_flow(GoogleSignInFailure.cancelled)]);
      await mountLogin(tester, google);
      await tester.enterText(
          find.byType(TextFormField).first, 'synthetic@example.com');
      await tester.tap(find.text('Continue with Google'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Cancelled'), findsNothing);
      expect(find.textContaining('[16]'), findsNothing);
      expect(find.text('synthetic@example.com'), findsOneWidget);
      expect(find.byType(LoginScreen), findsOneWidget);
      // The Google button is usable again.
      final button = tester.widget<OutlinedButton>(
          find.widgetWithText(OutlinedButton, 'Continue with Google'));
      expect(button.onPressed, isNotNull);
    });

    testWidgets('reopening Login after a cancellation shows no error',
        (tester) async {
      final google = _ScriptedGoogle([_flow(GoogleSignInFailure.cancelled)]);
      final container = ProviderContainer(overrides: [
        authRepositoryProvider
            .overrideWithValue(FakeAuthRepository()..loginResult = _session()),
        googleIdentityTokenProvider.overrideWithValue(google),
      ]);
      addTearDown(container.dispose);
      await mountLogin(tester, google, container: container);
      await tester.tap(find.text('Continue with Google'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await mountLogin(tester, google, container: container);
      expect(find.textContaining('Cancelled'), findsNothing);
      expect(container.read(authControllerProvider).hasError, isFalse);
    });

    testWidgets('configuration failure is localized (Russian)', (tester) async {
      final google = _ScriptedGoogle([
        _flow(GoogleSignInFailure.notConfigured,
            'Developer console is not set up correctly.'),
      ]);
      await mountLogin(tester, google, language: AppLanguage.russian);
      await tester.tap(find.text('Продолжить с Google'));
      await tester.pumpAndSettle();
      expect(find.text('Вход через Google не настроен для этой сборки.'),
          findsOneWidget);
      expect(find.textContaining('Developer console'), findsNothing);
    });

    testWidgets('unexpected failure is localized (Uzbek), not raw',
        (tester) async {
      final google = _ScriptedGoogle([
        _flow(GoogleSignInFailure.failed, '[10] Unexpected SDK failure'),
      ]);
      await mountLogin(tester, google, language: AppLanguage.uzbek);
      await tester.tap(find.text('Google bilan davom etish'));
      await tester.pumpAndSettle();
      expect(find.text('Google orqali kirish amalga oshmadi.'), findsOneWidget);
      expect(find.textContaining('[10]'), findsNothing);
    });
  });
}
