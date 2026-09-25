import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/core/location/location_service.dart';
import 'package:mushukistan_frontend/core/network/api_client.dart';
import 'package:mushukistan_frontend/core/routing/app_router.dart';
import 'package:mushukistan_frontend/core/network/api_error.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';
import 'package:mushukistan_frontend/core/onboarding/authenticated_onboarding_store.dart';
import 'package:mushukistan_frontend/features/auth/application/auth_controller.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_models.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_repository.dart';
import 'package:mushukistan_frontend/features/auth/infrastructure/auth_repository_impl.dart';

import '../../support/fakes.dart';

Widget _buildApp(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: Consumer(
      builder: (context, ref, _) {
        return MaterialApp.router(
          routerConfig: ref.watch(appRouterProvider),
        );
      },
    ),
  );
}

ProviderContainer _containerWithRepo(
  AuthRepository repo, {
  FakeApiClient? apiClient,
  FakeGoogleIdentityTokenProvider? googleIdentityTokens,
}) {
  final fakeApiClient = apiClient ?? FakeApiClient();
  fakeApiClient.handlers.putIfAbsent('GET feed', () {
    return (_) {
      return <String, Object?>{
        'items': <Object?>[
          <String, Object?>{
            'item_type': 'observation',
            'id': 'post-1',
            'cat': <String, Object?>{
              'id': 'cat-1',
              'name': 'Mushu',
              'cover_photo_url': null,
            },
            'author': <String, Object?>{
              'id': '11111111-1111-4111-8111-111111111111',
              'name': 'Sardor',
              'avatar_url': null,
            },
            'photo_url': 'https://example.com/cat.jpg',
            'thumb_url': 'https://example.com/cat-thumb.jpg',
            'description': 'Spotted near the park.',
            'location': <String, Object?>{
              'latitude': 41.2995,
              'longitude': 69.2401,
            },
            'created_at': '2026-07-01T10:00:00.000Z',
            'like_count': 3,
            'comment_count': 1,
            'is_liked_by_me': false,
          },
        ],
        'next_cursor': null,
        'limit': 30,
      };
    };
  });
  fakeApiClient.handlers.putIfAbsent('GET cats', () {
    return (_) {
      return <String, Object?>{
        'items': <Object?>[
          <String, Object?>{
            'id': 'cat-1',
            'name': 'Mushu',
            'status': 'healthy',
            'cover_photo_url': null,
            'canonical_location': <String, Object?>{
              'latitude': 41.2995,
              'longitude': 69.2401,
            },
            'last_seen_at': null,
            'total_observations': 1,
            'distance_meters': 12.0,
          },
        ],
        'next_cursor': null,
        'limit': 20,
      };
    };
  });
  fakeApiClient.handlers.putIfAbsent('GET posts/post-1', () {
    return (_) => <String, Object?>{
          'id': 'post-1',
          'cat': <String, Object?>{
            'id': 'cat-1',
            'name': 'Mushu',
            'status': 'healthy',
            'cover_photo_url': null,
          },
          'author': <String, Object?>{
            'id': '11111111-1111-4111-8111-111111111111',
            'name': 'Sardor',
            'avatar_url': null,
          },
          'photo_url': 'https://example.com/cat.jpg',
          'photo_urls': <String>['https://example.com/cat.jpg'],
          'thumb_url': 'https://example.com/cat-thumb.jpg',
          'description': 'Spotted near the park.',
          'location': <String, Object?>{
            'latitude': 41.2995,
            'longitude': 69.2401,
          },
          'created_at': '2026-07-01T10:00:00.000Z',
          'like_count': 3,
          'comment_count': 0,
          'is_liked_by_me': false,
          'is_public': true,
        };
  });
  fakeApiClient.handlers.putIfAbsent('GET posts/post-1/comments', () {
    return (_) => <String, Object?>{
          'items': <Object?>[],
          'next_cursor': null,
          'limit': 20,
        };
  });
  fakeApiClient.handlers.putIfAbsent('GET users/me', () {
    return (_) {
      return <String, Object?>{
        'id': '11111111-1111-4111-8111-111111111111',
        'email': 'user@example.com',
        'name': 'Sardor',
        'avatar_url': null,
        'bio': 'Cat lover',
        'registered_at': '2026-07-01T10:00:00.000Z',
        'observation_count': 12,
        'total_likes_received': 45,
        'comment_count': 17,
      };
    };
  });
  return ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(repo),
      googleIdentityTokenProvider.overrideWithValue(
        googleIdentityTokens ?? FakeGoogleIdentityTokenProvider(),
      ),
      apiClientProvider.overrideWithValue(fakeApiClient),
      authenticatedOnboardingStoreProvider.overrideWithValue(
        InMemoryAuthenticatedOnboardingStore(
          seenUserIds: {'11111111-1111-4111-8111-111111111111'},
        ),
      ),
      currentLocationProvider.overrideWith(
        (ref) async => const GeoPoint(latitude: 41.2995, longitude: 69.2401),
      ),
    ],
  );
}

Future<void> _pumpApp(WidgetTester tester, ProviderContainer container) async {
  tester.view.physicalSize = const Size(800, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(_buildApp(container));
  await tester.pump();
}

void main() {
  testWidgets('fresh guest opens the public feed', (tester) async {
    final container = _containerWithRepo(
      FakeAuthRepository(restoreResult: const SessionRestoreMissing()),
    );
    addTearDown(container.dispose);

    await _pumpApp(tester, container);
    await tester.pumpAndSettle();

    expect(
        container
            .read(appRouterProvider)
            .routeInformationProvider
            .value
            .uri
            .path,
        '/feed');
    expect(find.textContaining('Mushu'), findsWidgets);
    expect(find.text('Account required'), findsNothing);
  });

  testWidgets('guest public routes do not redirect to authentication',
      (tester) async {
    final container = _containerWithRepo(
      FakeAuthRepository(restoreResult: const SessionRestoreMissing()),
    );
    addTearDown(container.dispose);

    await _pumpApp(tester, container);
    await tester.pumpAndSettle();
    final router = container.read(appRouterProvider);
    const publicPaths = <String>[
      '/feed',
      '/map',
      '/leaderboards',
      '/posts/post-1',
      '/lost-pets/lost-1',
      '/adoption-posts/adoption-1',
      '/users/user-1',
      '/users/user-1/observations',
      '/users/user-1/comments',
    ];

    for (final path in publicPaths) {
      router.go(path);
      await tester.pump();
      expect(
        router.routeInformationProvider.value.uri.path,
        path,
        reason: '$path must remain public',
      );
    }
  });

  testWidgets('invalid and unavailable session restoration leave guest UI',
      (tester) async {
    for (final result in <SessionRestoreResult>[
      const SessionRestoreInvalid(message: 'Session expired.'),
      const SessionRestoreFailure(message: 'Backend unavailable.'),
    ]) {
      final container = _containerWithRepo(
        FakeAuthRepository(restoreResult: result),
      );
      await _pumpApp(tester, container);
      await tester.pumpAndSettle();

      expect(
        container
            .read(appRouterProvider)
            .routeInformationProvider
            .value
            .uri
            .path,
        '/feed',
      );
      expect(find.textContaining('Mushu'), findsWidgets);
      container.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('guest like action requests authentication', (tester) async {
    final container = _containerWithRepo(
      FakeAuthRepository(restoreResult: const SessionRestoreMissing()),
    );
    addTearDown(container.dispose);

    await _pumpApp(tester, container);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Like'));
    await tester.pumpAndSettle();
    expect(find.text('Account required'), findsOneWidget);
  });

  testWidgets('guest protected routes preserve their post-login destination',
      (tester) async {
    final container = _containerWithRepo(
      FakeAuthRepository(restoreResult: const SessionRestoreMissing()),
    );
    addTearDown(container.dispose);

    await _pumpApp(tester, container);
    await tester.pumpAndSettle();
    final router = container.read(appRouterProvider);

    for (final path in <String>[
      '/add',
      '/add/lost-pet',
      '/add/adoption',
      '/profile',
      '/report?type=post&id=post-1',
      '/posts/post-1/edit',
      '/moderation/reports',
    ]) {
      router.go(path);
      await tester.pumpAndSettle();
      final uri = router.routeInformationProvider.value.uri;
      expect(uri.path, '/auth-required');
      expect(uri.queryParameters['redirect'], path);
      expect(find.text('Account required'), findsOneWidget);
    }
  });

  testWidgets('successful login returns to the intended protected action',
      (tester) async {
    final repo = FakeAuthRepository(
      restoreResult: const SessionRestoreMissing(),
      loginResult: AuthSession.restored(
        accessToken: 'token-123',
        user: testUser(),
      ),
    );
    final container = _containerWithRepo(repo);
    addTearDown(container.dispose);

    await _pumpApp(tester, container);
    await tester.pumpAndSettle();
    final router = container.read(appRouterProvider);
    router.go('/add/lost-pet');
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Login'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).first,
      'user@example.com',
    );
    await tester.enterText(find.byType(TextFormField).last, 'password1');
    await tester.tap(find.widgetWithText(FilledButton, 'Login'));
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/add/lost-pet');
    expect(container.read(authControllerProvider).isAuthenticated, isTrue);
  });

  testWidgets('unauthenticated users are redirected away from protected routes',
      (tester) async {
    final container = _containerWithRepo(
      FakeAuthRepository(restoreResult: const SessionRestoreMissing()),
    );
    addTearDown(container.dispose);

    await _pumpApp(tester, container);
    final router = container.read(appRouterProvider);

    router.go('/profile');
    await tester.pumpAndSettle();

    expect(find.text('Account required'), findsOneWidget);
    expect(find.text('Continue browsing'), findsOneWidget);
  });

  testWidgets('authenticated users are redirected away from login',
      (tester) async {
    final container = _containerWithRepo(
      FakeAuthRepository(
        restoreResult: SessionRestoreSuccess(
          AuthSession.restored(
            accessToken: 'token-123',
            user: testUser(),
          ),
        ),
      ),
    );
    addTearDown(container.dispose);

    await _pumpApp(tester, container);
    await tester.pumpAndSettle();

    final router = container.read(appRouterProvider);
    router.go('/login');
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Feed')),
      findsOneWidget,
    );
  });

  testWidgets('non-moderators cannot open moderation routes', (tester) async {
    final container = _containerWithRepo(
      FakeAuthRepository(
        restoreResult: SessionRestoreSuccess(
          AuthSession.restored(accessToken: 'token-123', user: testUser()),
        ),
      ),
    );
    addTearDown(container.dispose);

    await _pumpApp(tester, container);
    await tester.pumpAndSettle();
    container.read(appRouterProvider).go('/moderation/reports');
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Profile'), findsOneWidget);
  });

  testWidgets('moderators can open moderation routes', (tester) async {
    final container = _containerWithRepo(
      FakeAuthRepository(
        restoreResult: SessionRestoreSuccess(
          AuthSession.restored(
            accessToken: 'token-123',
            user: testUser(isModerator: true),
          ),
        ),
      ),
    );
    addTearDown(container.dispose);

    await _pumpApp(tester, container);
    await tester.pumpAndSettle();
    container.read(appRouterProvider).go('/moderation/reports');
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Moderation reports'), findsOneWidget);
  });

  testWidgets('public feed remains available while restoration resolves',
      (tester) async {
    final repo = FakeAuthRepository();
    repo.restoreCompleter = Completer<SessionRestoreResult>();
    final container = _containerWithRepo(repo);
    addTearDown(container.dispose);

    await _pumpApp(tester, container);

    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Feed')),
      findsOneWidget,
    );
    expect(find.text('Join Mushukistan'), findsNothing);

    repo.restoreCompleter!.complete(const SessionRestoreMissing());
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Feed')),
      findsOneWidget,
    );
  });

  testWidgets(
      'expired access token silently refreshes once before entering the app',
      (tester) async {
    final apiClient = FakeApiClient();
    final tokenStore = FakeAuthTokenStore('expired-token', 'refresh-123');
    final refreshCompleter = Completer<Object?>();
    apiClient.setHandler('GET', 'users/me', (_) {
      throw const MushukistanApiException(
        kind: ApiFailureKind.unauthorized,
        code: 'UNAUTHORIZED',
        message: 'Missing or invalid Authorization header.',
      );
    });
    apiClient.setHandler('POST', 'auth/refresh', (call) {
      expect(call.authenticated, isFalse);
      expect(call.body, <String, Object?>{'refresh_token': 'refresh-123'});
      return refreshCompleter.future;
    });
    final repository = MushukistanAuthRepository(
      apiClient: apiClient,
      tokenStore: tokenStore,
    );
    final container = _containerWithRepo(repository, apiClient: apiClient);
    addTearDown(container.dispose);

    await _pumpApp(tester, container);
    await tester.pump();

    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Feed')),
      findsOneWidget,
    );
    expect(find.text('Join Mushukistan'), findsNothing);
    expect(find.text('Welcome back'), findsNothing);
    expect(apiClient.calls.where((call) => call.path == 'auth/refresh'),
        hasLength(1));

    refreshCompleter.complete(<String, Object?>{
      'access_token': 'token-456',
      'refresh_token': 'refresh-456',
      'token_type': 'Bearer',
      'expires_in': 3600,
      'user': testUser().toJson(),
    });
    await tester.pumpAndSettle();

    expect(
        container.read(authControllerProvider).phase, AuthPhase.authenticated);
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Feed')),
      findsOneWidget,
    );
    expect(find.text('Join Mushukistan'), findsNothing);
    expect(find.text('Welcome back'), findsNothing);
    expect(await tokenStore.read(), 'token-456');
    expect(await tokenStore.readRefreshToken(), 'refresh-456');
    expect(apiClient.calls.where((call) => call.path == 'auth/refresh'),
        hasLength(1));
  });

  testWidgets('login loading and error state are visible', (tester) async {
    final repo = FakeAuthRepository();
    repo.restoreResult = const SessionRestoreMissing();
    repo.loginCompleter = Completer<AuthSession>();
    final container = _containerWithRepo(repo);
    addTearDown(container.dispose);

    await _pumpApp(tester, container);
    await tester.pumpAndSettle();

    container.read(appRouterProvider).go('/login');
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byType(TextFormField).first, 'user@example.com');
    await tester.enterText(find.byType(TextFormField).last, 'password1');
    await tester.tap(find.text('Login'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    repo.loginCompleter!.complete(
      AuthSession.restored(
        accessToken: 'token-123',
        user: testUser(),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Feed')),
      findsOneWidget,
    );
  });

  testWidgets('login failures are displayed without corrupting state',
      (tester) async {
    final repo = FakeAuthRepository();
    repo.restoreResult = const SessionRestoreMissing();
    repo.loginError = const MushukistanApiException(
      kind: ApiFailureKind.unauthorized,
      code: 'INVALID_CREDENTIALS',
      message: 'Invalid email or password.',
    );
    final container = _containerWithRepo(repo);
    addTearDown(container.dispose);

    await _pumpApp(tester, container);
    await tester.pumpAndSettle();

    container.read(appRouterProvider).go('/login');
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byType(TextFormField).first, 'user@example.com');
    await tester.enterText(find.byType(TextFormField).last, 'password1');
    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();

    expect(find.text('Invalid email or password.'), findsOneWidget);
    expect(container.read(authControllerProvider).phase,
        AuthPhase.unauthenticated);
  });

  testWidgets('login shows Google sign-in when unauthenticated',
      (tester) async {
    final container = _containerWithRepo(
      FakeAuthRepository(restoreResult: const SessionRestoreMissing()),
    );
    addTearDown(container.dispose);

    await _pumpApp(tester, container);
    await tester.pumpAndSettle();

    container.read(appRouterProvider).go('/login');
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Google sign-in is unavailable.'), findsNothing);
  });

  testWidgets('auth navigation does not corrupt Google availability',
      (tester) async {
    final repo = FakeAuthRepository(
      restoreResult: const SessionRestoreMissing(),
      loginResult: AuthSession.restored(
        accessToken: 'token-123',
        user: testUser(email: 'google-user@example.com'),
      ),
    );
    final google = FakeGoogleIdentityTokenProvider(idToken: 'google-id-token');
    final container = _containerWithRepo(
      repo,
      googleIdentityTokens: google,
    );
    addTearDown(container.dispose);

    await _pumpApp(tester, container);
    await tester.pumpAndSettle();

    expect(find.text('Continue with Google'), findsNothing);
    expect(find.text('Join Mushukistan'), findsNothing);
    expect(find.text('Google sign-in is unavailable.'), findsNothing);

    container.read(appRouterProvider).go('/login');
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);

    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();

    expect(
        container.read(authControllerProvider).phase, AuthPhase.authenticated);
    expect(repo.registerCalls, 0);
    expect(repo.lastGoogleIdToken, 'google-id-token');
    expect(google.calls, 1);
  });

  testWidgets('existing Google user signs in without email registration',
      (tester) async {
    final repo = FakeAuthRepository(
      restoreResult: const SessionRestoreMissing(),
      loginResult: AuthSession.restored(
        accessToken: 'token-123',
        user: testUser(email: 'existing-google@example.com'),
      ),
    );
    final google = FakeGoogleIdentityTokenProvider(idToken: 'google-id-token');
    final container = _containerWithRepo(
      repo,
      googleIdentityTokens: google,
    );
    addTearDown(container.dispose);

    await _pumpApp(tester, container);
    await tester.pumpAndSettle();

    container.read(appRouterProvider).go('/login');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();

    expect(
        container.read(authControllerProvider).phase, AuthPhase.authenticated);
    expect(find.text('Join Mushukistan'), findsNothing);
    expect(repo.registerCalls, 0);
    expect(repo.lastGoogleAcceptTerms, isFalse);
    expect(repo.lastGoogleAcceptPrivacy, isFalse);
  });

  testWidgets('google login asks for legal consent before account creation',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repo = FakeAuthRepository(
      restoreResult: const SessionRestoreMissing(),
      loginResult: AuthSession.restored(
        accessToken: 'token-123',
        user: testUser(email: 'google-user@example.com'),
      ),
    );
    repo.loginError = const MushukistanApiException(
      kind: ApiFailureKind.validation,
      code: 'LEGAL_ACCEPTANCE_REQUIRED',
      message: 'Terms of Service and Privacy Policy acceptance is required.',
    );
    final google = FakeGoogleIdentityTokenProvider(idToken: 'google-id-token');
    final container = _containerWithRepo(
      repo,
      googleIdentityTokens: google,
    );
    addTearDown(container.dispose);

    await _pumpApp(tester, container);
    await tester.pumpAndSettle();

    container.read(appRouterProvider).go('/login');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();

    expect(find.text('Before you continue'), findsOneWidget);
    expect(find.text('Terms of Service'), findsWidgets);
    expect(find.text('Privacy Policy'), findsWidgets);
    expect(find.text('Google sign-in is unavailable.'), findsNothing);
    expect(container.read(authControllerProvider).pendingGoogleIdToken,
        'google-id-token');
    expect(google.calls, 1);

    repo.loginError = null;
    final termsCheckbox = find.byType(Checkbox).at(0);
    final privacyCheckbox = find.byType(Checkbox).at(1);
    await tester.ensureVisible(termsCheckbox);
    await tester.tap(termsCheckbox);
    await tester.ensureVisible(privacyCheckbox);
    await tester.tap(privacyCheckbox);
    await tester.pump();
    final continueButton = find.widgetWithText(FilledButton, 'Continue');
    await tester.ensureVisible(continueButton);
    await tester.tap(continueButton);
    await tester.pumpAndSettle();

    expect(repo.lastGoogleIdToken, 'google-id-token');
    expect(repo.lastGoogleAcceptTerms, isTrue);
    expect(repo.lastGoogleAcceptPrivacy, isTrue);
    expect(google.calls, 1);
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Feed')),
      findsOneWidget,
    );
  });

  testWidgets('registration loading and error state are visible',
      (tester) async {
    final repo = FakeAuthRepository();
    repo.restoreResult = const SessionRestoreMissing();
    repo.registerCompleter = Completer<VerificationRequirement>();
    final container = _containerWithRepo(repo);
    addTearDown(container.dispose);

    await _pumpApp(tester, container);
    await tester.pumpAndSettle();

    container.read(appRouterProvider).go('/register');
    await tester.pumpAndSettle();

    expect(find.text('Join Mushukistan'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(0), 'Sardor');
    await tester.enterText(
        find.byType(TextFormField).at(1), 'user@example.com');
    await tester.enterText(find.byType(TextFormField).at(2), 'password1');
    await tester.tap(find.byType(Checkbox).at(0));
    await tester.tap(find.byType(Checkbox).at(1));
    await tester.pump();
    final registerButton = find.widgetWithText(FilledButton, 'Register');
    await tester.ensureVisible(registerButton);
    await tester.tap(registerButton);
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(repo.lastRegisterCredentials?.preferredLanguage, 'en');
    expect(repo.lastRegisterCredentials?.acceptTerms, isTrue);
    expect(repo.lastRegisterCredentials?.acceptPrivacy, isTrue);

    repo.registerCompleter!.complete(
      const VerificationRequirement(
        email: 'user@example.com',
        devVerificationToken: 'dev-token',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Confirm your email'), findsOneWidget);
    expect(find.text('Verify now'), findsOneWidget);
  });

  testWidgets('email verification link submits token from route',
      (tester) async {
    final repo = FakeAuthRepository(
      restoreResult: const SessionRestoreMissing(),
    );
    final container = _containerWithRepo(repo);
    addTearDown(container.dispose);

    await _pumpApp(tester, container);
    await tester.pumpAndSettle();

    container.read(appRouterProvider).go('/verify-email?token=email-token');
    await tester.pumpAndSettle();

    expect(repo.lastVerifyEmailToken, 'email-token');
    expect(find.text('Email verified. You can sign in now.'), findsOneWidget);
    expect(find.text('Continue to login'), findsOneWidget);
  });

  testWidgets('email verification deep link survives session restore',
      (tester) async {
    final repo = FakeAuthRepository(
      restoreResult: const SessionRestoreMissing(),
    );
    repo.restoreCompleter = Completer<SessionRestoreResult>();
    final container = _containerWithRepo(repo);
    addTearDown(container.dispose);

    await _pumpApp(tester, container);

    container.read(appRouterProvider).go('/verify-email?token=email-token');
    await tester.pump();

    expect(repo.lastVerifyEmailToken, 'email-token');

    repo.restoreCompleter!.complete(const SessionRestoreMissing());
    await tester.pumpAndSettle();

    expect(find.text('Email verified. You can sign in now.'), findsOneWidget);
  });

  testWidgets('authenticated shell renders the current user and logs out',
      (tester) async {
    final repo = FakeAuthRepository(
      restoreResult: SessionRestoreSuccess(
        AuthSession.restored(
          accessToken: 'token-123',
          user: testUser(),
        ),
      ),
    );
    final container = _containerWithRepo(repo);
    addTearDown(container.dispose);

    await _pumpApp(tester, container);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();

    expect(find.text('Sardor'), findsWidgets);
    expect(find.text('user@example.com'), findsOneWidget);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Logout'));
    await tester.pumpAndSettle();

    expect(find.text('Log out?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Sardor'), findsWidgets);
    expect(repo.logoutCalled, isFalse);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Logout'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Logout'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Feed')),
      findsOneWidget,
    );
    expect(repo.logoutCalled, isTrue);
  });
}
