import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mushukistan_frontend/core/location/location_service.dart';
import 'package:mushukistan_frontend/core/navigation/settings_changes_guard.dart';
import 'package:mushukistan_frontend/core/network/api_client.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';
import 'package:mushukistan_frontend/core/onboarding/authenticated_onboarding_store.dart';
import 'package:mushukistan_frontend/core/routing/app_router.dart';
import 'package:mushukistan_frontend/core/theme/theme_controller.dart';
import 'package:mushukistan_frontend/features/auth/application/auth_controller.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_models.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_repository.dart';
import 'package:mushukistan_frontend/features/notifications/application/nearby_alerts.dart';
import 'package:mushukistan_frontend/features/notifications/application/notification_push.dart';

import '../../support/fakes.dart';

class _NoDevicePush extends DevicePushAccess {
  @override
  Future<DevicePushPermission> status() async => DevicePushPermission.web;
}

const _userId = '11111111-1111-4111-8111-111111111111';

FakeApiClient _apiClient() {
  final client = FakeApiClient()
    ..setHandler(
        'GET',
        'feed',
        (_) => {
              'items': <Object?>[],
              'next_cursor': null,
              'limit': 30,
            })
    ..setHandler(
        'GET',
        'users/me',
        (_) => {
              'id': _userId,
              'email': 'user@example.com',
              'name': 'Sardor',
              'registered_at': '2026-07-01T10:00:00.000Z',
              'observation_count': 0,
              'total_likes_received': 0,
              'comment_count': 0,
            });
  return client;
}

ProviderContainer _container(AuthRepository repository) {
  return ProviderContainer(overrides: [
    authRepositoryProvider.overrideWithValue(repository),
    googleIdentityTokenProvider
        .overrideWithValue(FakeGoogleIdentityTokenProvider()),
    apiClientProvider.overrideWithValue(_apiClient()),
    nearbyAlertsAndroidProvider.overrideWithValue(false),
    devicePushAccessProvider.overrideWithValue(_NoDevicePush()),
    authenticatedOnboardingStoreProvider.overrideWithValue(
      InMemoryAuthenticatedOnboardingStore(seenUserIds: {_userId}),
    ),
    currentLocationProvider.overrideWith(
      (ref) async => const GeoPoint(latitude: 41.2995, longitude: 69.2401),
    ),
  ]);
}

Future<GoRouter> _pumpApp(WidgetTester tester, ProviderContainer container,
    {Size size = const Size(390, 844)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: Consumer(
      builder: (context, ref, _) =>
          MaterialApp.router(routerConfig: ref.watch(appRouterProvider)),
    ),
  ));
  await tester.pump();
  return container.read(appRouterProvider);
}

String _path(GoRouter router) => router.routeInformationProvider.value.uri.path;

/// What the visible screen is, including pages opened with push.
String _visible(GoRouter router) => visibleRouteUri(router).path;

/// Records what the app tells Android: system exits (Back left to the system) and whether the
/// framework handles Back (what predictive Back uses to decide on the back-to-home animation).
class _AndroidBack {
  _AndroidBack(WidgetTester tester) {
    // Flutter only reports who handles Back to the engine while the app is in the foreground.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemNavigator.pop') exits++;
      if (call.method == 'SystemNavigator.setFrameworkHandlesBack') {
        frameworkHandlesBack = call.arguments as bool;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
  }

  int exits = 0;
  bool? frameworkHandlesBack;
}

/// One press of the Android system Back button.
Future<void> _back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

Future<GoRouter> _signedInApp(WidgetTester tester) async {
  final container = _container(FakeAuthRepository(
    restoreResult: SessionRestoreSuccess(
      AuthSession.restored(accessToken: 'access', user: testUser()),
    ),
  ));
  addTearDown(container.dispose);
  final router = await _pumpApp(tester, container);
  await tester.pumpAndSettle();
  expect(_path(router), '/feed');
  return router;
}

const _exitHint = 'Press Back again to exit';

void main() {
  group('main tabs', () {
    for (final tab in ['/map', '/add', '/leaderboards', '/profile']) {
      testWidgets('Back on the $tab root returns to Feed, not out of the app',
          (tester) async {
        final android = _AndroidBack(tester);
        final router = await _signedInApp(tester);

        router.go(tab);
        await tester.pumpAndSettle();
        expect(_path(router), tab);

        await _back(tester);
        expect(_path(router), '/feed');
        expect(android.exits, 0);
        expect(find.text(_exitHint), findsNothing);
      });
    }
  });

  group('nested screens', () {
    testWidgets('Back inside a tab returns to its parent, then to Feed',
        (tester) async {
      final android = _AndroidBack(tester);
      final router = await _signedInApp(tester);

      router.go('/profile');
      await tester.pumpAndSettle();
      router.go('/profile/settings');
      await tester.pumpAndSettle();

      await _back(tester);
      expect(_path(router), '/profile');
      await _back(tester);
      expect(_path(router), '/feed');
      expect(android.exits, 0);
    });

    testWidgets('Back from a detail opened from the Feed returns to the Feed',
        (tester) async {
      final android = _AndroidBack(tester);
      final router = await _signedInApp(tester);

      unawaited(router.push('/users/user-1'));
      await tester.pumpAndSettle();
      expect(_visible(router), '/users/user-1');

      await _back(tester);
      expect(_visible(router), '/feed');
      expect(android.exits, 0);
      expect(find.text(_exitHint), findsNothing);
    });

    for (final settle in [false, true]) {
      testWidgets(
          'Settings reopened ${settle ? 'later' : 'in the next frame'} keeps '
          'its unsaved-changes guard', (tester) async {
        final container = _container(FakeAuthRepository(
          restoreResult: SessionRestoreSuccess(
            AuthSession.restored(accessToken: 'access', user: testUser()),
          ),
        ));
        addTearDown(container.dispose);
        final router = await _pumpApp(tester, container);
        await tester.pumpAndSettle();
        router.go('/profile/settings');
        await tester.pumpAndSettle();

        // The old Settings screen is disposed here; its deferred cleanup must not clear the
        // guard that the reopened screen registers.
        router.go('/profile');
        settle ? await tester.pumpAndSettle() : await tester.pump();
        router.go('/profile/settings');
        await tester.pumpAndSettle();
        expect(container.read(settingsDiscardChangesProvider), isNotNull);

        await tester
            .tap(find.widgetWithText(RadioListTile<AppThemeMode>, 'Dark'));
        await tester.pumpAndSettle();
        expect(container.read(settingsHasUnsavedChangesProvider), isTrue);
        await tester.tap(find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Feed'),
        ));
        await tester.pumpAndSettle();
        expect(find.text('Discard changes'), findsOneWidget);
        await tester.tap(find.text('Discard changes'));
        await tester.pumpAndSettle();
        expect(_path(router), '/feed');
        expect(container.read(settingsHasUnsavedChangesProvider), isFalse);
      });
    }

    testWidgets('unsaved settings still ask before Back leaves them',
        (tester) async {
      final router = await _signedInApp(tester);
      router.go('/profile');
      await tester.pumpAndSettle();
      router.go('/profile/settings');
      await tester.pumpAndSettle();
      await tester
          .tap(find.widgetWithText(RadioListTile<AppThemeMode>, 'Dark'));
      await tester.pumpAndSettle();

      await _back(tester);
      expect(find.text('Keep editing'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(_path(router), '/profile/settings');

      await _back(tester);
      await tester.tap(find.text('Discard changes'));
      await tester.pumpAndSettle();
      expect(_path(router), '/profile');
    });
  });

  group('Feed root', () {
    testWidgets('a second Back within 2 seconds leaves the app to the system',
        (tester) async {
      final android = _AndroidBack(tester);
      await _signedInApp(tester);

      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(android.exits, 0);
      expect(find.text(_exitHint), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 1500));
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(android.exits, 1);
      await tester.pumpAndSettle();
    });

    testWidgets('after 2 seconds the next Back asks again', (tester) async {
      final android = _AndroidBack(tester);
      await _signedInApp(tester);

      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 2100));
      await tester.pumpAndSettle();
      expect(find.text(_exitHint), findsNothing);

      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(android.exits, 0);
      expect(find.text(_exitHint), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(android.exits, 1);
      await tester.pumpAndSettle();
    });

    testWidgets('opening another screen cancels a pending exit',
        (tester) async {
      final android = _AndroidBack(tester);
      final router = await _signedInApp(tester);

      await tester.binding.handlePopRoute();
      await tester.pump();
      unawaited(router.push('/users/user-1'));
      await tester.pumpAndSettle();
      await _back(tester);
      expect(_visible(router), '/feed');

      // Still within 2 seconds of the first press, but the exit was cancelled.
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(android.exits, 0);
      expect(find.text(_exitHint), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('switching tabs cancels a pending exit', (tester) async {
      final android = _AndroidBack(tester);
      final router = await _signedInApp(tester);

      await tester.binding.handlePopRoute();
      await tester.pump();
      router.go('/map');
      await tester.pump();
      await _back(tester);
      expect(_path(router), '/feed');

      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(android.exits, 0);
      await tester.pumpAndSettle();
    });

    testWidgets('predictive Back: the system is told in advance who handles it',
        (tester) async {
      final android = _AndroidBack(tester);
      final router = await _signedInApp(tester);
      // Feed, nothing pending: the app shows the hint, so the framework handles Back.
      expect(android.frameworkHandlesBack, isTrue);

      await tester.binding.handlePopRoute();
      await tester.pump();
      // Exit armed: Back belongs to the system (back-to-home animation).
      expect(android.frameworkHandlesBack, isFalse);

      await tester.pump(const Duration(milliseconds: 2100));
      await tester.pumpAndSettle();
      expect(android.frameworkHandlesBack, isTrue);

      router.go('/map');
      await tester.pumpAndSettle();
      expect(android.frameworkHandlesBack, isTrue);
    });
  });

  group('notifications', () {
    testWidgets('warm start: opens on top of the current screen, Back returns',
        (tester) async {
      final android = _AndroidBack(tester);
      final router = await _signedInApp(tester);
      router.go('/map');
      await tester.pumpAndSettle();

      openNotificationDestination(router, '/users/user-1');
      await tester.pumpAndSettle();
      expect(_visible(router), '/users/user-1');

      await _back(tester);
      expect(_visible(router), '/map');
      await _back(tester);
      expect(_path(router), '/feed');
      expect(android.exits, 0);
    });

    testWidgets('the same destination is not opened twice', (tester) async {
      final router = await _signedInApp(tester);

      openNotificationDestination(router, '/users/user-1');
      await tester.pumpAndSettle();
      openNotificationDestination(router, '/users/user-1');
      await tester.pumpAndSettle();
      expect(
        router.routerDelegate.currentConfiguration.matches
            .where((match) => match.matchedLocation == '/users/user-1'),
        hasLength(1),
      );

      await _back(tester);
      expect(_visible(router), '/feed');
    });

    testWidgets('cold start: the destination opens over the Feed after restore',
        (tester) async {
      final android = _AndroidBack(tester);
      final restore = Completer<SessionRestoreResult>();
      final container =
          _container(FakeAuthRepository()..restoreCompleter = restore);
      addTearDown(container.dispose);
      final router = await _pumpApp(tester, container);
      // The push handler holds the open until the session check answers.
      restore.complete(SessionRestoreSuccess(
        AuthSession.restored(accessToken: 'access', user: testUser()),
      ));
      await tester.pumpAndSettle();

      openNotificationDestination(router, '/posts/post-1?comments=1');
      await tester.pumpAndSettle();
      expect(_visible(router), '/posts/post-1');

      await _back(tester);
      expect(_visible(router), '/feed');
      expect(android.exits, 0);
      expect(find.text(_exitHint), findsNothing);
    });

    testWidgets('on a sign-in page the redirects keep deciding',
        (tester) async {
      final container = _container(
        FakeAuthRepository(restoreResult: const SessionRestoreMissing()),
      );
      addTearDown(container.dispose);
      final router = await _pumpApp(tester, container);
      await tester.pumpAndSettle();
      router.go('/login');
      await tester.pumpAndSettle();

      openNotificationDestination(router, '/notifications');
      await tester.pumpAndSettle();
      // A guest is sent to sign in for the protected destination, not stacked on /login.
      expect(_path(router), '/auth-required');
    });
  });

  group('view on map', () {
    testWidgets('keeps the location and Back from the map goes to Feed',
        (tester) async {
      final android = _AndroidBack(tester);
      final router = await _signedInApp(tester);
      unawaited(router.push('/users/user-1'));
      await tester.pumpAndSettle();

      // What the detail screens' "View on map" chip does.
      router.go('/map?lat=41.3&lon=69.2&lostPetId=lost-1');
      await tester.pumpAndSettle();
      final uri = router.routeInformationProvider.value.uri;
      expect(uri.path, '/map');
      expect(uri.queryParameters,
          {'lat': '41.3', 'lon': '69.2', 'lostPetId': 'lost-1'});

      await _back(tester);
      expect(_path(router), '/feed');
      expect(android.exits, 0);
    });
  });

  group('auth restoration during protected shell navigation', () {
    // Before the fix every timing below failed with "Duplicate GlobalKey detected in widget
    // tree" (StatefulNavigationShellState): the redirect's animated page kept the replaced shell
    // route mounted while the restored session re-added the shell.
    for (final size in const [Size(390, 844), Size(800, 1000)]) {
      for (final wait in const [
        Duration.zero,
        Duration(milliseconds: 16),
        Duration(milliseconds: 50),
      ]) {
        testWidgets(
            'no Duplicate GlobalKey at ${size.width.toInt()}px, '
            'answer after ${wait.inMilliseconds} ms', (tester) async {
          final restore = Completer<SessionRestoreResult>();
          final repo = FakeAuthRepository()..restoreCompleter = restore;
          final container = _container(repo);
          addTearDown(container.dispose);
          final router = await _pumpApp(tester, container, size: size);
          await tester.pump(const Duration(milliseconds: 50));

          router.go('/add/lost-pet');
          await tester.pump();
          await tester.pump(wait);
          expect(_path(router), '/auth-required');

          // Restoration answers while the redirect's page is still being shown in.
          restore.complete(SessionRestoreSuccess(
            AuthSession.restored(accessToken: 'access', user: testUser()),
          ));
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(_path(router), '/add/lost-pet');
        });
      }
    }
  });
}
