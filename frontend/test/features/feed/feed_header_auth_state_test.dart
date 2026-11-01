import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/core/localization/language_controller.dart';
import 'package:mushukistan_frontend/core/network/api_error.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';
import 'package:mushukistan_frontend/core/storage/token_store.dart';
import 'package:mushukistan_frontend/core/theme/app_theme.dart';
import 'package:mushukistan_frontend/features/auth/application/auth_controller.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_models.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_repository.dart';
import 'package:mushukistan_frontend/features/auth/infrastructure/auth_repository_impl.dart';
import 'package:mushukistan_frontend/features/feed/presentation/screens/feed_screen.dart';
import 'package:mushukistan_frontend/features/notifications/presentation/notification_center_screen.dart';

import '../../support/fakes.dart';

const _pendingKey = ValueKey('feed-header-session-pending');

FakeApiClient _feedClient() => FakeApiClient()
  ..setHandler(
      'GET',
      'feed',
      (_) => {
            'items': <Object?>[],
            'next_cursor': null,
            'limit': 30,
          });

/// Pumps the Feed with a real [AuthController] over [repository]. No reconnect timers are
/// scheduled, so a test never leaves background work behind.
Future<ProviderContainer> _pumpFeed(
  WidgetTester tester,
  AuthRepository repository, {
  AuthTokenStore? tokenStore,
  AppLanguage language = AppLanguage.english,
}) async {
  tester.view.physicalSize = const Size(390, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(overrides: [
    mushukistanApiProvider
        .overrideWithValue(MushukistanApi(client: _feedClient())),
    appLanguageProvider.overrideWith((ref) => language),
    authControllerProvider.overrideWith(
      (ref) => AuthController(
        repository,
        FakeGoogleIdentityTokenProvider(),
        tokenStore: tokenStore,
        reconnectBackoff: const <Duration>[],
      ),
    ),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(theme: AppTheme.light, home: const FeedScreen()),
  ));
  await tester.pump();
  return container;
}

void _expectPending() {
  expect(find.byKey(_pendingKey), findsOneWidget);
  expect(find.text('Login'), findsNothing);
  // The introduction's sign-up button is guest UI too.
  expect(find.text('Create account'), findsNothing);
  expect(find.byType(NotificationBell), findsNothing);
}

void _expectGuest() {
  expect(find.text('Login'), findsOneWidget);
  expect(find.text('Create account'), findsOneWidget);
  expect(find.byKey(_pendingKey), findsNothing);
  expect(find.byType(NotificationBell), findsNothing);
}

void _expectSignedIn() {
  expect(find.byType(NotificationBell), findsOneWidget);
  expect(find.text('Login'), findsNothing);
  expect(find.byKey(_pendingKey), findsNothing);
}

void main() {
  testWidgets('restoring a stored session shows a neutral placeholder',
      (tester) async {
    final restore = Completer<SessionRestoreResult>();
    final repo = FakeAuthRepository()..restoreCompleter = restore;
    final container = await _pumpFeed(tester, repo);

    expect(container.read(authControllerProvider).isResolving, isTrue);
    _expectPending();
    // The feed itself is not blocked while the session is checked.
    expect(find.text('Recent'), findsOneWidget);

    restore.complete(const SessionRestoreMissing());
    await tester.pumpAndSettle();
  });

  testWidgets('placeholder keeps the title in place and is localized',
      (tester) async {
    final restore = Completer<SessionRestoreResult>();
    final repo = FakeAuthRepository()..restoreCompleter = restore;
    await _pumpFeed(tester, repo, language: AppLanguage.russian);

    final titleBefore = tester.getRect(find.text('Mushukistan'));
    final slot = tester.getSize(find.byKey(_pendingKey));
    expect(slot, const Size.square(kMinInteractiveDimension));
    expect(
      tester.getSemantics(find.byKey(_pendingKey)).label,
      isNotEmpty,
    );

    restore.complete(SessionRestoreSuccess(
      AuthSession.restored(accessToken: 'token', user: testUser()),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(NotificationBell), findsOneWidget);
    expect(tester.getRect(find.text('Mushukistan')), titleBefore);
  });

  testWidgets('a restored session shows account controls', (tester) async {
    final repo = FakeAuthRepository(
      restoreResult: SessionRestoreSuccess(
        AuthSession.restored(accessToken: 'token', user: testUser()),
      ),
    );
    await _pumpFeed(tester, repo);
    await tester.pumpAndSettle();

    _expectSignedIn();
  });

  testWidgets('a confirmed guest sees the login button', (tester) async {
    await _pumpFeed(
      tester,
      FakeAuthRepository(restoreResult: const SessionRestoreMissing()),
    );
    await tester.pumpAndSettle();

    _expectGuest();
  });

  testWidgets(
      'a network failure with stored credentials is not shown as a logout',
      (tester) async {
    final repo = FakeAuthRepository(
      restoreResult: const SessionRestoreFailure(
        message: 'Network request failed.',
        retryable: true,
      ),
    );
    final container = await _pumpFeed(tester, repo);
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      container.read(authControllerProvider).phase,
      AuthPhase.sessionUnavailable,
    );
    expect(find.text('Login'), findsNothing);
    expect(find.byKey(_pendingKey), findsNothing);
    expect(find.byType(NotificationBell), findsNothing);
  });

  testWidgets(
      'an unexpected restore error with stored credentials keeps the session',
      (tester) async {
    final store = FakeAuthTokenStore('access-token', 'refresh-token');
    final repo = FakeAuthRepository()..restoreError = StateError('boom');
    final container = await _pumpFeed(tester, repo, tokenStore: store);
    await tester.pump(const Duration(milliseconds: 50));

    final state = container.read(authControllerProvider);
    expect(state.phase, AuthPhase.sessionUnavailable);
    expect(state.isAuthenticated, isFalse);
    expect(find.text('Login'), findsNothing);
    // Nothing was cleared: the user is still signed in as far as we know.
    expect(await store.read(), 'access-token');
    expect(await store.readRefreshToken(), 'refresh-token');
  });

  testWidgets(
      'an unexpected restore error without stored credentials is a guest',
      (tester) async {
    final repo = FakeAuthRepository()..restoreError = StateError('boom');
    final container = await _pumpFeed(
      tester,
      repo,
      tokenStore: FakeAuthTokenStore(),
    );
    await tester.pumpAndSettle();

    expect(
      container.read(authControllerProvider).phase,
      AuthPhase.unauthenticated,
    );
    _expectGuest();
  });

  testWidgets(
      'credentials rejected after a failed refresh end in guest UI and are cleared',
      (tester) async {
    final store = FakeAuthTokenStore('expired-access', 'revoked-refresh');
    final api = FakeApiClient()
      ..setHandler('GET', 'users/me', (_) {
        throw const MushukistanApiException(
          kind: ApiFailureKind.unauthorized,
          code: 'UNAUTHORIZED',
          message: 'Missing or invalid Authorization header.',
        );
      })
      ..setHandler('POST', 'auth/refresh', (_) {
        throw const MushukistanApiException(
          kind: ApiFailureKind.unauthorized,
          code: 'INVALID_REFRESH_TOKEN',
          message: 'Invalid or expired session.',
        );
      });
    final repo = MushukistanAuthRepository(apiClient: api, tokenStore: store);
    final container = await _pumpFeed(tester, repo, tokenStore: store);
    await tester.pumpAndSettle();

    expect(
      container.read(authControllerProvider).phase,
      AuthPhase.unauthenticated,
    );
    _expectGuest();
    expect(await store.read(), isNull);
    expect(await store.readRefreshToken(), isNull);
  });

  testWidgets('restoring then authenticated never flashes the guest login',
      (tester) async {
    final restore = Completer<SessionRestoreResult>();
    final repo = FakeAuthRepository()..restoreCompleter = restore;
    await _pumpFeed(tester, repo);

    for (var frame = 0; frame < 5; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
      _expectPending();
    }
    restore.complete(SessionRestoreSuccess(
      AuthSession.restored(accessToken: 'token', user: testUser()),
    ));
    // Every frame from here on is either still pending or signed in, never guest.
    for (var frame = 0; frame < 5; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.text('Login'), findsNothing, reason: 'frame $frame');
    }
    await tester.pumpAndSettle();
    _expectSignedIn();
  });
}
