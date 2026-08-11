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
}) {
  final fakeApiClient = apiClient ?? FakeApiClient();
  fakeApiClient.setHandler('GET', 'feed', (_) {
    return <String, Object?>{
      'items': <Object?>[
        <String, Object?>{
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
        },
      ],
      'next_cursor': null,
      'limit': 30,
    };
  });
  fakeApiClient.setHandler('GET', 'cats', (_) {
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
  });
  fakeApiClient.setHandler('GET', 'users/me', (_) {
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
  });
  return ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(repo),
      googleIdentityTokenProvider
          .overrideWithValue(FakeGoogleIdentityTokenProvider()),
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
  await tester.pumpWidget(_buildApp(container));
  await tester.pump();
}

void main() {
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

    expect(find.text('Welcome back'), findsOneWidget);
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

    expect(find.text('Mushukistan'), findsOneWidget);
  });

  testWidgets('restoration state stays on the gate until it resolves',
      (tester) async {
    final repo = FakeAuthRepository();
    repo.restoreCompleter = Completer<SessionRestoreResult>();
    final container = _containerWithRepo(repo);
    addTearDown(container.dispose);

    await _pumpApp(tester, container);

    expect(find.text('Restoring session...'), findsOneWidget);
    expect(find.text('Welcome back'), findsNothing);

    repo.restoreCompleter!.complete(const SessionRestoreMissing());
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
  });

  testWidgets('login loading and error state are visible', (tester) async {
    final repo = FakeAuthRepository();
    repo.restoreResult = const SessionRestoreMissing();
    repo.loginCompleter = Completer<AuthSession>();
    final container = _containerWithRepo(repo);
    addTearDown(container.dispose);

    await _pumpApp(tester, container);
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

    expect(find.text('Mushukistan'), findsOneWidget);
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

    await tester.enterText(
        find.byType(TextFormField).first, 'user@example.com');
    await tester.enterText(find.byType(TextFormField).last, 'password1');
    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();

    expect(find.text('Invalid email or password.'), findsOneWidget);
    expect(container.read(authControllerProvider).phase,
        AuthPhase.unauthenticated);
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

    await tester.tap(find.text('Create an account'));
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

    await tester.tap(find.byTooltip('Logout'));
    await tester.pumpAndSettle();

    expect(find.text('Log out?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Sardor'), findsWidgets);
    expect(repo.logoutCalled, isFalse);

    await tester.tap(find.byTooltip('Logout'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Logout'));
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
    expect(repo.logoutCalled, isTrue);
  });
}
