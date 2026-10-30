import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/core/localization/language_controller.dart';
import 'package:mushukistan_frontend/core/location/location_service.dart';
import 'package:mushukistan_frontend/core/network/api_client.dart';
import 'package:mushukistan_frontend/core/routing/app_router.dart';
import 'package:mushukistan_frontend/app.dart';
import 'package:mushukistan_frontend/core/network/api_error.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';
import 'package:mushukistan_frontend/core/onboarding/authenticated_onboarding_store.dart';
import 'package:mushukistan_frontend/features/auth/application/auth_controller.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_models.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_repository.dart';
import 'package:mushukistan_frontend/features/auth/infrastructure/auth_repository_impl.dart';
import 'package:mushukistan_frontend/features/auth/presentation/screens/login_screen.dart';
import 'package:mushukistan_frontend/features/auth/presentation/screens/session_unavailable_screen.dart';
import 'package:mushukistan_frontend/features/auth/presentation/widgets/google_sign_in_entry_button.dart';
import 'package:mushukistan_frontend/features/auth/presentation/widgets/legal_consent_text.dart';
import 'package:mushukistan_frontend/features/feed/presentation/screens/feed_screen.dart';
import 'package:mushukistan_frontend/features/notifications/application/notification_push.dart';
import 'package:mushukistan_frontend/features/notifications/application/nearby_alerts.dart';
import 'package:mushukistan_frontend/features/profile/presentation/screens/profile_screen.dart';

import '../../support/fakes.dart';

class _BrowserNotificationAccess extends DevicePushAccess {
  @override
  Future<DevicePushPermission> status() async => DevicePushPermission.web;
}

Widget _buildApp(ProviderContainer container,
    {bool useProductionRoot = false}) {
  return UncontrolledProviderScope(
    container: container,
    child: useProductionRoot
        ? const MushukistanApp()
        : Consumer(
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
      nearbyAlertsAndroidProvider.overrideWithValue(false),
      devicePushAccessProvider.overrideWithValue(_BrowserNotificationAccess()),
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

Future<void> _pumpApp(
  WidgetTester tester,
  ProviderContainer container, {
  bool useProductionRoot = false,
}) async {
  tester.view.physicalSize = const Size(800, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    _buildApp(container, useProductionRoot: useProductionRoot),
  );
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

  testWidgets('push lifecycle remains mounted on root detail routes',
      (tester) async {
    final repo = FakeAuthRepository(
      restoreResult: SessionRestoreSuccess(AuthSession.restored(
        accessToken: 'access-a',
        user: testUser(),
      )),
    );
    final container = _containerWithRepo(repo);
    addTearDown(container.dispose);

    await _pumpApp(tester, container, useProductionRoot: true);
    await tester.pumpAndSettle();
    expect(find.byType(NotificationLifecycle), findsOneWidget);

    container.read(appRouterProvider).go('/posts/post-1');
    await tester.pumpAndSettle();
    expect(find.byType(NotificationLifecycle), findsOneWidget);
  });

  testWidgets('invalid session restoration leaves guest UI', (tester) async {
    final container = _containerWithRepo(
      FakeAuthRepository(
        restoreResult: const SessionRestoreInvalid(message: 'Session expired.'),
      ),
    );
    addTearDown(container.dispose);
    await _pumpApp(tester, container);
    await tester.pumpAndSettle();

    expect(
      container.read(appRouterProvider).routeInformationProvider.value.uri.path,
      '/feed',
    );
    expect(find.textContaining('Mushu'), findsWidgets);
    expect(find.text('Login'), findsWidgets);
    expect(find.text('Create account'), findsWidgets);
  });

  testWidgets('unavailable backend keeps the session and shows no guest UI',
      (tester) async {
    final container = _containerWithRepo(
      FakeAuthRepository(
        restoreResult: const SessionRestoreFailure(
          message: 'Backend unavailable.',
        ),
      ),
    );
    await _pumpApp(tester, container);
    await tester.pump(const Duration(milliseconds: 50));

    final state = container.read(authControllerProvider);
    expect(state.phase, AuthPhase.sessionUnavailable);
    expect(
      container.read(appRouterProvider).routeInformationProvider.value.uri.path,
      '/feed',
    );
    // The signed-out welcome card and Login button would wrongly suggest a logout.
    expect(find.text('Login'), findsNothing);
    expect(find.text('Create account'), findsNothing);
    expect(find.text('Can’t reach the server'), findsOneWidget);
    expect(find.text('Retry'), findsWidgets);
    container.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
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

  testWidgets('successful password login from Login immediately opens Feed',
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
    router.go('/login');
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextFormField).first,
      'user@example.com',
    );
    await tester.enterText(find.byType(TextFormField).last, 'password1');
    await tester.tap(find.widgetWithText(FilledButton, 'Login'));
    await tester.pumpAndSettle();

    expect(container.read(authControllerProvider).isAuthenticated, isTrue);
    expect(router.routeInformationProvider.value.uri.path, '/feed');
    expect(
      find.byType(FeedScreen),
      findsOneWidget,
    );
  });

  testWidgets('unauthenticated users are redirected away from protected routes',
      (tester) async {
    final container = _containerWithRepo(
      FakeAuthRepository(restoreResult: const SessionRestoreMissing()),
    );
    addTearDown(container.dispose);

    await _pumpApp(tester, container);
    final router = container.read(appRouterProvider);

    for (final path in [
      '/profile',
      '/profile/edit',
      '/profile/settings/security',
      '/add',
      '/posts/example/edit',
      '/lost-pets/example/edit',
      '/adoption-posts/example/edit',
    ]) {
      router.go(path);
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/auth-required');
      expect(find.text('Account required'), findsOneWidget);
    }
    expect(find.text('Continue browsing'), findsOneWidget);
  });

  testWidgets('legacy notification settings link redirects to Settings child',
      (tester) async {
    final api = FakeApiClient()
      ..setHandler(
          'GET',
          'notifications/preferences',
          (_) => {
                'push_comments': true,
                'push_replies': true,
                'push_followups': true,
                'nearby_enabled': false,
                'inactivity_enabled': false,
                'push_available': false,
                'alert_location': null,
              });
    final container = _containerWithRepo(
      FakeAuthRepository(
        restoreResult: SessionRestoreSuccess(AuthSession.restored(
          accessToken: 'token-123',
          user: testUser(),
        )),
      ),
      apiClient: api,
    );
    addTearDown(container.dispose);
    await _pumpApp(tester, container);
    await tester.pumpAndSettle();
    final router = container.read(appRouterProvider);
    router.go('/notifications/settings');
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path,
        '/profile/settings/notifications');
    expect(find.text('Notifications'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
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
      find.byType(FeedScreen),
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

    expect(find.byType(ProfileScreen), findsOneWidget);
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
      find.byType(FeedScreen),
      findsOneWidget,
    );
    expect(find.text('Join Mushukistan'), findsNothing);

    repo.restoreCompleter!.complete(const SessionRestoreMissing());
    await tester.pumpAndSettle();

    expect(
      find.byType(FeedScreen),
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
      find.byType(FeedScreen),
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
      find.byType(FeedScreen),
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
      find.byType(FeedScreen),
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

    expect(find.text('Email or password is incorrect.'), findsOneWidget);
    expect(container.read(authControllerProvider).phase,
        AuthPhase.unauthenticated);
  });

  for (final route in ['/login', '/register']) {
    testWidgets('Google collision on $route confirms password inside sign-in',
        (tester) async {
      final repo = FakeAuthRepository(
        restoreResult: const SessionRestoreMissing(),
        loginResult:
            AuthSession.restored(accessToken: 'token-123', user: testUser()),
      );
      repo.loginError = const MushukistanApiException(
        kind: ApiFailureKind.conflict,
        code: 'GOOGLE_PASSWORD_REQUIRED',
        message: 'Confirm password',
      );
      final google = FakeGoogleIdentityTokenProvider();
      final container = _containerWithRepo(repo, googleIdentityTokens: google);
      addTearDown(container.dispose);
      await _pumpApp(tester, container);
      await tester.pumpAndSettle();
      container.read(appRouterProvider).go(route);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue with Google'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm your password'), findsOneWidget);
      final field = find.descendant(
          of: find.byType(AlertDialog), matching: find.byType(TextField));
      await tester.enterText(field, 'Wrong1234');
      repo.loginError = const MushukistanApiException(
        kind: ApiFailureKind.unauthorized,
        code: 'INVALID_CREDENTIALS',
        message: 'Wrong password',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(repo.lastGooglePassword, 'Wrong1234');
      expect(container.read(authControllerProvider).isAuthenticated, isFalse);
      await tester.enterText(field, 'Original123');
      repo.loginError = null;
      await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
      await tester.pumpAndSettle();
      expect(container.read(authControllerProvider).isAuthenticated, isTrue);
      expect(repo.lastGooglePassword, 'Original123');
      expect(repo.lastGoogleIdToken, 'google-id-token');
      expect(google.calls, 1);
      expect(find.byType(AlertDialog), findsNothing);
    });
  }

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

  for (final route in ['/login', '/register']) {
    for (final account in <String, String>{
      'new Google user': 'new-google@example.com',
      'existing Google user': 'existing-google@example.com',
    }.entries) {
      testWidgets('${account.key} authenticates from $route', (tester) async {
        final repo = FakeAuthRepository(
          restoreResult: const SessionRestoreMissing(),
          loginResult: AuthSession.restored(
            accessToken: 'token-123',
            user: testUser(email: account.value),
          ),
        );
        final google =
            FakeGoogleIdentityTokenProvider(idToken: 'google-id-token');
        final container = _containerWithRepo(
          repo,
          googleIdentityTokens: google,
        );
        addTearDown(container.dispose);

        await _pumpApp(tester, container);
        await tester.pumpAndSettle();
        container.read(appRouterProvider).go(route);
        await tester.pumpAndSettle();

        expect(find.text('Terms of Service'), findsWidgets);
        expect(find.text('Privacy Policy'), findsWidgets);
        expect(find.text('Continue with Google'), findsOneWidget);
        await tester.tap(find.text('Continue with Google'));
        await tester.pumpAndSettle();

        expect(
          container.read(authControllerProvider).phase,
          AuthPhase.authenticated,
        );
        expect(repo.lastGoogleIdToken, 'google-id-token');
        expect(repo.registerCalls, 0);
        expect(
          find.byType(FeedScreen),
          findsOneWidget,
        );
        expect(
            container
                .read(appRouterProvider)
                .routeInformationProvider
                .value
                .uri
                .path,
            '/feed');
      });
    }
  }

  for (final route in ['/login', '/register']) {
    testWidgets('web Google callback immediately leaves $route',
        (tester) async {
      if (!kIsWeb) return;

      final repo = FakeAuthRepository(
        restoreResult: const SessionRestoreMissing(),
        loginResult: AuthSession.restored(
          accessToken: 'token-123',
          user: testUser(email: 'google-user@example.com'),
        ),
      );
      final container = _containerWithRepo(repo);
      addTearDown(container.dispose);

      await _pumpApp(
        tester,
        container,
        useProductionRoot: true,
      );
      await tester.pumpAndSettle();
      container.read(appRouterProvider).go(route);
      await tester.pumpAndSettle();

      final button = tester.widget<GoogleSignInEntryButton>(
        find.byType(GoogleSignInEntryButton),
      );
      await button.onIdToken!('google-id-token');
      await tester.pumpAndSettle();

      expect(container.read(authControllerProvider).isAuthenticated, isTrue);
      expect(
          container
              .read(appRouterProvider)
              .routeInformationProvider
              .value
              .uri
              .path,
          '/feed');
      expect(
        find.byType(FeedScreen),
        findsOneWidget,
      );
    });
  }

  for (final route in ['/login', '/register']) {
    testWidgets('Google verification error stays clear on $route',
        (tester) async {
      final repo = FakeAuthRepository(
        restoreResult: const SessionRestoreMissing(),
      );
      repo.loginError = const MushukistanApiException(
        kind: ApiFailureKind.unauthorized,
        code: 'INVALID_GOOGLE_TOKEN',
        message: 'Invalid token',
      );
      final container = _containerWithRepo(
        repo,
        googleIdentityTokens: FakeGoogleIdentityTokenProvider(),
      );
      addTearDown(container.dispose);

      await _pumpApp(tester, container);
      await tester.pumpAndSettle();
      container.read(appRouterProvider).go(route);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue with Google'));
      await tester.pumpAndSettle();

      expect(find.text('Could not verify this Google account. Try again.'),
          findsOneWidget);
      expect(container.read(authControllerProvider).phase,
          AuthPhase.unauthenticated);
      expect(repo.registerCalls, 0);
    });
  }

  testWidgets('google login shows linked legal notice without a retry screen',
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

    expect(find.byType(LegalAgreementText), findsOneWidget);
    expect(find.text('Terms of Service'), findsWidgets);
    expect(find.text('Privacy Policy'), findsWidgets);
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    expect(google.calls, 1);
    expect(repo.lastGoogleIdToken, 'google-id-token');
    expect(find.byType(Checkbox), findsNothing);
    expect(
      find.byType(FeedScreen),
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
      find.byType(FeedScreen),
      findsOneWidget,
    );
    expect(repo.logoutCalled, isTrue);
  });

  testWidgets('switching accounts without a restart switches the UI language',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    addTearDown(() => FlutterSecureStorage.setMockInitialValues({}));
    final userA = testUser(preferredLanguage: 'en');
    final userB = testUser(
      id: '22222222-2222-4222-8222-222222222222',
      email: 'b@example.com',
      name: 'User B',
      preferredLanguage: 'ru',
    );
    final repo = FakeAuthRepository(
      restoreResult: SessionRestoreSuccess(
        AuthSession.restored(accessToken: 'access-a', user: userA),
      ),
      loginResult: AuthSession.restored(accessToken: 'access-b', user: userB),
    );
    final container = _containerWithRepo(repo);
    await _pumpApp(tester, container, useProductionRoot: true);
    await tester.pumpAndSettle();
    final controller = container.read(authControllerProvider.notifier);
    await controller.restoreSession();
    await tester.pumpAndSettle();
    expect(container.read(appLanguageProvider), AppLanguage.english);

    await controller.logout();
    await tester.pumpAndSettle();
    await controller.login(
        const AuthCredentials(email: 'b@example.com', password: 'Password123'));
    await tester.pumpAndSettle();
    expect(container.read(appLanguageProvider), AppLanguage.russian);

    container.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('account switch clears cached profile and viewer overrides', () async {
    final userA = testUser();
    final userB = testUser(
      id: '22222222-2222-4222-8222-222222222222',
      email: 'b@example.com',
      name: 'User B',
    );
    final repo = FakeAuthRepository(
      restoreResult: SessionRestoreSuccess(
        AuthSession.restored(accessToken: 'access-a', user: userA),
      ),
      loginResult: AuthSession.restored(accessToken: 'access-b', user: userB),
    );
    final api = FakeApiClient();
    var activeProfile = userA;
    api.setHandler('GET', 'users/me', (_) => activeProfile.toJson());
    final container = _containerWithRepo(repo, apiClient: api);
    addTearDown(container.dispose);
    container.read(appRouterProvider);
    final controller = container.read(authControllerProvider.notifier);
    await controller.restoreSession();
    expect((await container.read(profileMeProvider.future)).name, userA.name);
    container.read(postLikeOverridesProvider.notifier).state = {
      'post-1': const LikeData(liked: true, likeCount: 10),
    };

    await controller.logout();
    expect(container.read(postLikeOverridesProvider), isEmpty);
    activeProfile = userB;
    await controller.login(
        const AuthCredentials(email: 'b@example.com', password: 'Password123'));
    expect(container.read(currentUserProvider)?.id, userB.id);
    expect((await container.read(profileMeProvider.future)).name, userB.name);
    expect(container.read(postLikeOverridesProvider), isEmpty);
  });

  testWidgets('slow logout immediately leaves protected profile',
      (tester) async {
    final repo = FakeAuthRepository(
      restoreResult: SessionRestoreSuccess(AuthSession.restored(
        accessToken: 'access-a',
        user: testUser(),
      )),
    )..logoutCompleter = Completer<void>();
    final container = _containerWithRepo(repo);
    addTearDown(container.dispose);
    await _pumpApp(tester, container);
    await tester.pumpAndSettle();
    final router = container.read(appRouterProvider);
    router.go('/profile');
    await tester.pumpAndSettle();

    final logout = container.read(authControllerProvider.notifier).logout();
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/feed');
    expect(container.read(authControllerProvider).user, isNull);
    repo.logoutCompleter!.complete();
    await logout;
  });

  group('login opened from the feed Login button', () {
    setUp(() => FlutterSecureStorage.setMockInitialValues({}));

    // Found on a real Android device: the feed opens Login with `context.push`, and after a
    // successful sign-in the app stayed on the Login screen until it was restarted.
    testWidgets(
        'a successful login from the pushed Login screen reaches the feed',
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
      await _pumpApp(tester, container, useProductionRoot: true);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Login'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);

      await tester.enterText(
          find.byType(TextFormField).first, 'user@example.com');
      await tester.enterText(find.byType(TextFormField).last, 'password1');
      await tester.tap(find.widgetWithText(FilledButton, 'Login'));
      await tester.pumpAndSettle();

      expect(container.read(authControllerProvider).isAuthenticated, isTrue);
      expect(find.byType(LoginScreen), findsNothing,
          reason: 'the Login screen must not stay on top after signing in');
      expect(find.byType(FeedScreen), findsOneWidget);
    });

    testWidgets('the same holds after logging out and in again',
        (tester) async {
      final repo = FakeAuthRepository(
        restoreResult: SessionRestoreSuccess(
          AuthSession.restored(accessToken: 'token', user: testUser()),
        ),
        loginResult: AuthSession.restored(
          accessToken: 'token-2',
          user: testUser(),
        ),
      );
      final container = _containerWithRepo(repo);
      addTearDown(container.dispose);
      await _pumpApp(tester, container, useProductionRoot: true);
      await tester.pumpAndSettle();
      await container.read(authControllerProvider.notifier).logout();
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Login'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byType(TextFormField).first, 'user@example.com');
      await tester.enterText(find.byType(TextFormField).last, 'password1');
      await tester.tap(find.widgetWithText(FilledButton, 'Login'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsNothing);
      expect(find.byType(FeedScreen), findsOneWidget);
    });
  });

  group('versioned legal acceptance', () {
    const pendingId = '11111111-1111-4111-8111-111111111111';

    FakeAuthRepository pendingRepo({
      Object? acceptError,
      MushukistanUser? accepted,
    }) {
      return FakeAuthRepository(
        restoreResult: SessionRestoreSuccess(
          AuthSession.restored(
            accessToken: 'token',
            user: testUser(id: pendingId, legalAcceptanceRequired: true),
          ),
        ),
      )
        ..acceptLegalError = acceptError
        ..acceptLegalResult = accepted ?? testUser(id: pendingId);
    }

    Future<ProviderContainer> start(
      WidgetTester tester,
      FakeAuthRepository repo,
    ) async {
      final container = _containerWithRepo(repo);
      addTearDown(container.dispose);
      await _pumpApp(tester, container, useProductionRoot: true);
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('a user with outdated acceptance sees the update screen first',
        (tester) async {
      final repo = pendingRepo();
      await start(tester, repo);

      expect(
          find.text('We updated our Terms and Privacy Policy'), findsWidgets);
      expect(find.text('Accept and continue'), findsOneWidget);
      // Opening the app is never acceptance.
      expect(repo.acceptLegalCalls, 0);
    });

    testWidgets('the update title appears once, in every language, untruncated',
        (tester) async {
      final repo = pendingRepo();
      final container = await start(tester, repo);
      for (final entry in {
        AppLanguage.english: 'We updated our Terms and Privacy Policy',
        AppLanguage.russian:
            'Мы обновили Условия и Политику конфиденциальности',
        AppLanguage.uzbek:
            'Foydalanish shartlari va Maxfiylik siyosatini yangiladik',
      }.entries) {
        container.read(appLanguageProvider.notifier).state = entry.key;
        await tester.pumpAndSettle();
        expect(find.text(entry.value), findsOneWidget, reason: '${entry.key}');
        expect(find.byType(AppBar), findsNothing);
      }
    });

    testWidgets('accepting records the named versions and continues',
        (tester) async {
      final repo = pendingRepo();
      await start(tester, repo);

      await tester.tap(find.text('Accept and continue'));
      await tester.pumpAndSettle();

      expect(repo.acceptLegalCalls, 1);
      expect(repo.lastAcceptedTermsVersion, '2026-10-15');
      expect(repo.lastAcceptedPrivacyVersion, '2026-10-30');
      expect(find.text('Accept and continue'), findsNothing);
      expect(find.byType(FeedScreen), findsOneWidget);
    });

    testWidgets('a failed acceptance keeps the screen, explains and can retry',
        (tester) async {
      final repo = pendingRepo(
        acceptError: const MushukistanApiException(
          kind: ApiFailureKind.network,
          code: 'NETWORK_ERROR',
          message: 'offline',
        ),
      );
      await start(tester, repo);

      await tester.tap(find.text('Accept and continue'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not save your acceptance'),
          findsOneWidget);
      expect(find.text('Accept and continue'), findsOneWidget);

      repo.acceptLegalError = null;
      await tester.tap(find.text('Accept and continue'));
      await tester.pumpAndSettle();
      expect(repo.acceptLegalCalls, 2);
      expect(find.byType(FeedScreen), findsOneWidget);
    });

    testWidgets('changed documents are explained, not silently accepted',
        (tester) async {
      final repo = pendingRepo(
        acceptError: const MushukistanApiException(
          kind: ApiFailureKind.conflict,
          code: 'LEGAL_VERSION_MISMATCH',
          message: 'changed',
        ),
      );
      await start(tester, repo);
      await tester.tap(find.text('Accept and continue'));
      await tester.pumpAndSettle();
      expect(find.textContaining('documents changed again'), findsOneWidget);
      expect(find.text('Accept and continue'), findsOneWidget);
    });

    testWidgets('both documents can be read and logout stays available',
        (tester) async {
      final repo = pendingRepo();
      await start(tester, repo);

      await tester.tap(find.text('Terms of Service'));
      await tester.pumpAndSettle();
      expect(find.text('Effective date: 2026-10-15'), findsOneWidget);
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Privacy Policy'));
      await tester.pumpAndSettle();
      expect(find.text('Effective date: 2026-10-30'), findsOneWidget);
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Logout'));
      await tester.pumpAndSettle();
      expect(repo.logoutCalled, isTrue);
      expect(find.text('Accept and continue'), findsNothing);
      expect(repo.acceptLegalCalls, 0, reason: 'logging out is not acceptance');
    });

    testWidgets('a user with current acceptance is not interrupted',
        (tester) async {
      final repo = FakeAuthRepository(
        restoreResult: SessionRestoreSuccess(
          AuthSession.restored(accessToken: 'token', user: testUser()),
        ),
      );
      await start(tester, repo);
      expect(find.text('Accept and continue'), findsNothing);
      expect(find.byType(FeedScreen), findsOneWidget);
    });

    testWidgets('account switching evaluates each account on its own',
        (tester) async {
      final repo = FakeAuthRepository(
        restoreResult: SessionRestoreSuccess(
          AuthSession.restored(accessToken: 'token', user: testUser()),
        ),
        loginResult: AuthSession.restored(
          accessToken: 'token-b',
          user: testUser(
            id: '22222222-2222-4222-8222-222222222222',
            email: 'b@example.com',
            legalAcceptanceRequired: true,
          ),
        ),
      );
      final container = await start(tester, repo);
      expect(find.text('Accept and continue'), findsNothing);

      final controller = container.read(authControllerProvider.notifier);
      await controller.logout();
      await tester.pumpAndSettle();
      await controller.login(const AuthCredentials(
          email: 'b@example.com', password: 'Password123'));
      await tester.pumpAndSettle();
      expect(find.text('Accept and continue'), findsOneWidget);
      expect(repo.acceptLegalCalls, 0);
    });
  });

  group('session outage routing', () {
    SessionRestoreResult confirmed() => SessionRestoreSuccess(
          AuthSession.restored(accessToken: 'access-a', user: testUser()),
        );
    const outage = SessionRestoreFailure(message: 'Backend unavailable.');

    final retryOnScreen = find.descendant(
      of: find.byType(SessionUnavailableScreen),
      matching: find.text('Retry'),
    );

    String path(ProviderContainer container) => container
        .read(appRouterProvider)
        .routeInformationProvider
        .value
        .uri
        .path;

    testWidgets(
        'direct navigation to /profile during an outage shows retry UI, not sign-in',
        (tester) async {
      final repo = FakeAuthRepository(restoreResult: outage);
      final container = _containerWithRepo(repo);
      await _pumpApp(tester, container);
      await tester.pumpAndSettle();

      container.read(appRouterProvider).go('/profile');
      await tester.pumpAndSettle();

      expect(path(container), '/session-unavailable');
      expect(find.text('Can’t reach the server'), findsWidgets);
      expect(retryOnScreen, findsOneWidget);
      expect(find.text('Login'), findsNothing);
      expect(find.text('Create account'), findsNothing);
      expect(find.byType(ProfileScreen), findsNothing);
      container.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
        'cold load of a protected URL parked on sign-in while checking ends on the retry screen',
        (tester) async {
      // The browser reload case found in the real-browser run: the URL is requested while the
      // session check is still running, then the check ends as "server unreachable".
      final repo = FakeAuthRepository()
        ..restoreCompleter = Completer<SessionRestoreResult>();
      final container = _containerWithRepo(repo);
      await _pumpApp(tester, container);
      await tester.pump(const Duration(milliseconds: 50));
      container.read(appRouterProvider).go('/profile');
      // The progress spinner animates forever, so settle by a fixed interval instead.
      await tester.pump(const Duration(milliseconds: 400));
      expect(path(container), startsWith('/auth-required'));

      repo.restoreCompleter!.complete(outage);
      await tester.pumpAndSettle();

      expect(path(container), '/session-unavailable');
      expect(find.text('Login'), findsNothing);

      // Recovery returns to the page that was requested originally.
      repo.restoreCompleter = null;
      repo.restoreResult = confirmed();
      await tester.tap(retryOnScreen);
      await tester.pumpAndSettle();
      expect(path(container), '/profile');
      expect(find.byType(ProfileScreen), findsOneWidget);
      container.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('Retry restores the session and returns to the requested page',
        (tester) async {
      final repo = FakeAuthRepository(restoreResult: outage);
      final container = _containerWithRepo(repo);
      await _pumpApp(tester, container);
      await tester.pumpAndSettle();
      container.read(appRouterProvider).go('/profile');
      await tester.pumpAndSettle();
      expect(path(container), '/session-unavailable');

      // Still down: pressing Retry keeps the user on the same screen, signed in.
      await tester.tap(retryOnScreen);
      await tester.pumpAndSettle();
      expect(path(container), '/session-unavailable');
      expect(container.read(authControllerProvider).phase,
          AuthPhase.sessionUnavailable);

      // Backend returns.
      repo.restoreResult = confirmed();
      await tester.tap(retryOnScreen);
      await tester.pumpAndSettle();

      expect(container.read(authControllerProvider).isAuthenticated, isTrue);
      expect(path(container), '/profile');
      expect(find.byType(ProfileScreen), findsOneWidget);
      container.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('automatic re-check recovers without user action',
        (tester) async {
      final repo = FakeAuthRepository(restoreResult: outage);
      final container = _containerWithRepo(repo);
      await _pumpApp(tester, container);
      await tester.pumpAndSettle();
      container.read(appRouterProvider).go('/notifications');
      await tester.pumpAndSettle();
      expect(path(container), '/session-unavailable');

      repo.restoreResult = confirmed();
      await tester
          .pump(const Duration(seconds: 4)); // first automatic attempt (3 s)
      await tester.pumpAndSettle();

      expect(container.read(authControllerProvider).isAuthenticated, isTrue);
      expect(path(container), '/notifications');
      container.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
        'cold start during an outage: feed stays public without signed-out UI and recovers',
        (tester) async {
      final repo = FakeAuthRepository(restoreResult: outage);
      final container = _containerWithRepo(repo);
      await _pumpApp(tester, container);
      await tester.pumpAndSettle();

      expect(path(container), '/feed');
      expect(find.text('Login'), findsNothing);
      expect(find.text('Create account'), findsNothing);
      expect(find.text('Can’t reach the server'), findsOneWidget);

      repo.restoreResult = confirmed();
      await tester.tap(find.text('Retry').first);
      await tester.pumpAndSettle();

      expect(container.read(authControllerProvider).isAuthenticated, isTrue);
      expect(find.text('Can’t reach the server'), findsNothing);
      expect(find.text('Login'), findsNothing);
      container.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
        'a confirmed-invalid answer while waiting ends in the sign-in flow',
        (tester) async {
      final repo = FakeAuthRepository(restoreResult: outage);
      final container = _containerWithRepo(repo);
      await _pumpApp(tester, container);
      await tester.pumpAndSettle();
      container.read(appRouterProvider).go('/profile');
      await tester.pumpAndSettle();

      repo.restoreResult =
          const SessionRestoreInvalid(message: 'Session expired.');
      await tester.tap(retryOnScreen);
      await tester.pumpAndSettle();

      expect(container.read(authControllerProvider).phase,
          AuthPhase.unauthenticated);
      expect(path(container), '/auth-required');
      expect(find.text('Login'), findsWidgets);
      container.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
        'actions that need a session do not offer sign-in during an outage',
        (tester) async {
      final repo = FakeAuthRepository(restoreResult: outage);
      final container = _containerWithRepo(repo);
      await _pumpApp(tester, container);
      await tester.pumpAndSettle();

      container.read(appRouterProvider).push('/auth-required?redirect=%2Ffeed');
      await tester.pumpAndSettle();

      expect(find.text('Can’t reach the server'), findsWidgets);
      expect(find.text('Login'), findsNothing);
      container.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('moderator routes are held back by the outage, not by sign-in',
        (tester) async {
      final repo = FakeAuthRepository(restoreResult: outage);
      final container = _containerWithRepo(repo);
      await _pumpApp(tester, container);
      await tester.pumpAndSettle();

      container.read(appRouterProvider).go('/moderation/reports');
      await tester.pumpAndSettle();

      expect(path(container), '/session-unavailable');
      container.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('after explicit logout protected pages require sign-in again',
        (tester) async {
      final repo = FakeAuthRepository(restoreResult: confirmed());
      final container = _containerWithRepo(repo);
      addTearDown(container.dispose);
      await _pumpApp(tester, container);
      await tester.pumpAndSettle();
      await container.read(authControllerProvider.notifier).logout();
      await tester.pumpAndSettle();

      container.read(appRouterProvider).go('/profile');
      await tester.pumpAndSettle();
      expect(path(container), '/auth-required');
      expect(find.text('Can’t reach the server'), findsNothing);
    });

    for (final (language, title, message, retry) in [
      (
        AppLanguage.russian,
        'Не удаётся связаться с сервером',
        'Вы по-прежнему вошли в аккаунт.',
        'Повторить',
      ),
      (
        AppLanguage.uzbek,
        'Serverga ulanib bo‘lmadi',
        'Siz hisobingizdan chiqmadingiz.',
        'Qayta urinish',
      ),
    ]) {
      testWidgets('outage screen is localized: ${language.code}',
          (tester) async {
        final repo = FakeAuthRepository(restoreResult: outage);
        final container = _containerWithRepo(repo);
        container.read(appLanguageProvider.notifier).state = language;
        await _pumpApp(tester, container);
        await tester.pumpAndSettle();
        container.read(appRouterProvider).go('/profile');
        await tester.pumpAndSettle();

        expect(find.text(title), findsWidgets);
        expect(find.textContaining(message), findsWidgets);
        expect(
          find.descendant(
            of: find.byType(SessionUnavailableScreen),
            matching: find.text(retry),
          ),
          findsOneWidget,
        );
        expect(find.text('Can’t reach the server'), findsNothing);
        container.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }

    testWidgets(
        'saved language is used on a cold start during an outage and follows later changes',
        (tester) async {
      FlutterSecureStorage.setMockInitialValues(
          {'mushukistan_app_language': 'ru'});
      addTearDown(() => FlutterSecureStorage.setMockInitialValues({}));
      final repo = FakeAuthRepository(restoreResult: outage);
      final container = _containerWithRepo(repo);
      await _pumpApp(tester, container, useProductionRoot: true);
      await tester.pumpAndSettle();
      container.read(appRouterProvider).go('/profile');
      await tester.pumpAndSettle();

      expect(container.read(appLanguageProvider), AppLanguage.russian);
      expect(find.text('Не удаётся связаться с сервером'), findsWidgets);
      expect(find.text('Can’t reach the server'), findsNothing);

      // A language change is persisted for the next cold start.
      container.read(appLanguageProvider.notifier).state = AppLanguage.uzbek;
      await tester.pumpAndSettle();
      expect(
        await const FlutterSecureStorage()
            .read(key: 'mushukistan_app_language'),
        'uz',
      );
      container.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('without a saved language the app starts in English',
        (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final repo = FakeAuthRepository(restoreResult: outage);
      final container = _containerWithRepo(repo);
      await _pumpApp(tester, container, useProductionRoot: true);
      await tester.pumpAndSettle();
      container.read(appRouterProvider).go('/profile');
      await tester.pumpAndSettle();
      expect(find.text('Can’t reach the server'), findsWidgets);
      container.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a signed-in user mid-session is not affected by later outages',
        (tester) async {
      final repo = FakeAuthRepository(restoreResult: confirmed());
      final container = _containerWithRepo(repo);
      addTearDown(container.dispose);
      await _pumpApp(tester, container);
      await tester.pumpAndSettle();
      container.read(appRouterProvider).go('/profile');
      await tester.pumpAndSettle();
      expect(find.byType(ProfileScreen), findsOneWidget);

      // The API now fails every call; auth state and route must not change by themselves.
      repo.restoreResult = outage;
      await tester.pump(const Duration(seconds: 30));
      expect(container.read(authControllerProvider).isAuthenticated, isTrue);
      expect(path(container), '/profile');
      expect(repo.restoreCalls, 1,
          reason: 'no background polling while signed in');
    });
  });
}
