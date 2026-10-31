// Interactions between the auth header (Issue #4), Android Back and routing (Issue #2) and
// resume revalidation (Issue #3). Each feature has its own tests; these drive the real app root
// with real lifecycle events and system Back, where the features meet.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mushukistan_frontend/app.dart';
import 'package:mushukistan_frontend/core/lifecycle/app_resume.dart';
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
import 'package:mushukistan_frontend/features/notifications/presentation/notification_center_screen.dart';

import '../support/fakes.dart';

class _NoDevicePush extends DevicePushAccess {
  @override
  Future<DevicePushPermission> status() async => DevicePushPermission.web;
}

const _userId = '11111111-1111-4111-8111-111111111111';
const _pending = ValueKey('feed-header-session-pending');
const _exitHint = 'Press Back again to exit';

Map<String, Object?> _post(String id) => {
      'item_type': 'observation',
      'id': id,
      'kind': 'observation',
      'cat': {'id': 'cat-$id', 'name': 'Cat $id', 'status': 'healthy'},
      'author': {'id': 'author-1', 'name': 'Amina'},
      'photo_url': 'invalid:',
      'photo_urls': ['invalid:'],
      'description': 'Story $id',
      'created_at': '2026-09-01T10:00:00Z',
      'like_count': 0,
      'comment_count': 0,
      'is_liked_by_me': false,
    };

class _App {
  _App(this.tester, this.container, this.repo, this.client);

  final WidgetTester tester;
  final ProviderContainer container;
  final FakeAuthRepository repo;
  final FakeApiClient client;
  Duration now = const Duration(hours: 1);
  int exits = 0;

  GoRouter get router => container.read(appRouterProvider);
  AuthState get auth => container.read(authControllerProvider);
  String get path => router.routeInformationProvider.value.uri.path;
  String get visible => visibleRouteUri(router).path;

  int requests(String path) =>
      client.calls.where((call) => call.path == path).length;

  /// Real lifecycle events, in Android's order, through the app's own observer.
  void awayFor(Duration duration) {
    for (final state in const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    now += duration;
    for (final state in const [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
  }

  /// One press of the Android system Back button.
  Future<void> back() async {
    await tester.binding.handlePopRoute();
    await tester.pump();
  }
}

Future<_App> _pumpApp(
  WidgetTester tester, {
  SessionRestoreResult? restore,
  Completer<SessionRestoreResult>? slowRestore,
  List<String> feed = const ['a', 'b'],
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final repo = FakeAuthRepository(
    restoreResult: restore ??
        SessionRestoreSuccess(
          AuthSession.restored(accessToken: 'token', user: testUser()),
        ),
  )..restoreCompleter = slowRestore;
  final client = FakeApiClient()
    ..setHandler(
        'GET',
        'feed',
        (_) => {
              'items': [for (final id in feed) _post(id)],
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
            })
    ..setHandler('GET', 'notifications/unread-count', (_) => {'count': 0})
    ..setHandler('GET', 'notifications',
        (_) => {'items': <Object?>[], 'next_cursor': null, 'limit': 20});
  late _App app;
  final container = ProviderContainer(overrides: [
    authRepositoryProvider.overrideWithValue(repo),
    googleIdentityTokenProvider
        .overrideWithValue(FakeGoogleIdentityTokenProvider()),
    apiClientProvider.overrideWithValue(client),
    nearbyAlertsAndroidProvider.overrideWithValue(false),
    devicePushAccessProvider.overrideWithValue(_NoDevicePush()),
    authenticatedOnboardingStoreProvider.overrideWithValue(
      InMemoryAuthenticatedOnboardingStore(seenUserIds: {_userId}),
    ),
    currentLocationProvider.overrideWith(
      (ref) async => const GeoPoint(latitude: 41.2995, longitude: 69.2401),
    ),
    monotonicClockProvider.overrideWithValue(() => app.now),
  ]);
  addTearDown(container.dispose);
  app = _App(tester, container, repo, client);
  tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'SystemNavigator.pop') app.exits++;
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null));
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: const MushukistanApp(),
  ));
  await tester.pump();
  return app;
}

void main() {
  testWidgets(
      'resume during startup restore: placeholder stays, no second check',
      (tester) async {
    final slow = Completer<SessionRestoreResult>();
    final app = await _pumpApp(tester, slowRestore: slow);
    await tester.pump(const Duration(milliseconds: 50));
    expect(app.auth.isResolving, isTrue);
    expect(find.byKey(_pending), findsOneWidget);
    final restores = app.repo.restoreCalls;

    // Long enough for both content and session revalidation.
    app.awayFor(const Duration(minutes: 45));
    await tester.pump(const Duration(milliseconds: 50));
    expect(app.repo.restoreCalls, restores,
        reason: 'no check on top of restore');
    expect(find.byKey(_pending), findsOneWidget);
    expect(find.text('Login'), findsNothing);

    slow.complete(SessionRestoreSuccess(
      AuthSession.restored(accessToken: 'token', user: testUser()),
    ));
    await tester.pumpAndSettle();
    expect(app.auth.isAuthenticated, isTrue);
    expect(find.byKey(_pending), findsNothing);
    expect(find.byType(NotificationBell), findsOneWidget);
  });

  testWidgets('revalidation after 30 min offline keeps the signed-in header',
      (tester) async {
    final app = await _pumpApp(tester);
    await tester.pumpAndSettle();
    app.repo.restoreResult = const SessionRestoreFailure(
      message: 'Network request failed.',
      retryable: true,
    );
    final restores = app.repo.restoreCalls;

    app.awayFor(const Duration(minutes: 40));
    await tester.pump();
    // The quiet check never shows the startup placeholder or the guest button.
    expect(find.byKey(_pending), findsNothing);
    expect(find.text('Login'), findsNothing);
    await tester.pumpAndSettle();
    expect(app.repo.restoreCalls, restores + 1);
    expect(app.auth.isAuthenticated, isTrue);
    expect(find.byType(NotificationBell), findsOneWidget);
    expect(find.text('Login'), findsNothing);
  });

  testWidgets('logout while a revalidation is running ends signed out',
      (tester) async {
    final app = await _pumpApp(tester);
    await tester.pumpAndSettle();
    final slow = app.repo.restoreCompleter = Completer<SessionRestoreResult>();

    app.awayFor(const Duration(minutes: 40));
    await tester.pump();
    await app.container.read(authControllerProvider.notifier).logout();
    await tester.pumpAndSettle();
    slow.complete(SessionRestoreSuccess(
      AuthSession.restored(accessToken: 'token', user: testUser()),
    ));
    await tester.pumpAndSettle();

    expect(app.auth.phase, AuthPhase.unauthenticated);
    expect(find.text('Login'), findsOneWidget);
    app.router.go('/profile');
    await tester.pumpAndSettle();
    expect(app.path, '/auth-required');
  });

  testWidgets(
      'after a long absence on another tab, Feed refreshes once and '
      'Back still works', (tester) async {
    final app = await _pumpApp(tester);
    await tester.pumpAndSettle();
    app.router.go('/map');
    await tester.pumpAndSettle();
    final feeds = app.requests('feed');
    final unread = app.requests('notifications/unread-count');

    app.awayFor(const Duration(minutes: 10));
    await tester.pumpAndSettle();
    // The Feed tab stays mounted and is revalidated once; listeners do not multiply requests.
    expect(app.requests('feed'), feeds + 1);
    expect(app.requests('notifications/unread-count'), unread + 1);

    await app.back();
    await tester.pumpAndSettle();
    expect(app.path, '/feed');
    expect(app.requests('feed'), feeds + 1, reason: 'switching tabs reuses it');
    expect(app.exits, 0);

    await app.back();
    expect(find.text(_exitHint), findsOneWidget);
    expect(app.exits, 0);
    await app.back();
    expect(app.exits, 1);
    await tester.pumpAndSettle();
  });

  testWidgets(
      'cold-start notification after a slow restore, then a long absence',
      (tester) async {
    final slow = Completer<SessionRestoreResult>();
    final app = await _pumpApp(tester, slowRestore: slow);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Login'), findsNothing);
    }
    slow.complete(SessionRestoreSuccess(
      AuthSession.restored(accessToken: 'token', user: testUser()),
    ));
    await tester.pumpAndSettle();
    openNotificationDestination(app.router, '/notifications');
    await tester.pumpAndSettle();
    expect(app.visible, '/notifications');
    expect(find.byType(NotificationCenterScreen), findsOneWidget);
    final inbox = app.requests('notifications');

    app.awayFor(const Duration(minutes: 10));
    await tester.pumpAndSettle();
    expect(app.visible, '/notifications', reason: 'navigation is kept');
    expect(app.requests('notifications'), inbox + 1);

    await app.back();
    await tester.pumpAndSettle();
    expect(app.visible, '/feed');
    expect(find.byType(NotificationBell), findsOneWidget);
    expect(app.exits, 0);
  });

  testWidgets(
      'protected tab route during restore, no Duplicate GlobalKey, '
      'then resume', (tester) async {
    final slow = Completer<SessionRestoreResult>();
    final app = await _pumpApp(tester, slowRestore: slow);
    await tester.pump(const Duration(milliseconds: 50));
    app.router.go('/add/lost-pet');
    await tester.pump(const Duration(milliseconds: 50));
    expect(app.path, '/auth-required');

    slow.complete(SessionRestoreSuccess(
      AuthSession.restored(accessToken: 'token', user: testUser()),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(app.path, '/add/lost-pet');

    app.awayFor(const Duration(minutes: 40));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(app.path, '/add/lost-pet', reason: 'form left alone');
    expect(app.auth.isAuthenticated, isTrue);
  });

  testWidgets('unsaved Settings survive a long absence and still guard Back',
      (tester) async {
    final app = await _pumpApp(tester);
    await tester.pumpAndSettle();
    app.router.go('/profile/settings');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(RadioListTile<AppThemeMode>, 'Dark'));
    await tester.pumpAndSettle();

    app.awayFor(const Duration(minutes: 45));
    await tester.pumpAndSettle();
    expect(app.path, '/profile/settings');
    expect(app.container.read(settingsHasUnsavedChangesProvider), isTrue);
    final dark = tester.widget<RadioGroup<AppThemeMode>>(
      find.byType(RadioGroup<AppThemeMode>),
    );
    expect(dark.groupValue, AppThemeMode.dark);

    await app.back();
    await tester.pumpAndSettle();
    expect(find.text('Discard changes'), findsOneWidget);
  });

  testWidgets('New posts after a long absence, then Back on the Feed',
      (tester) async {
    final app =
        await _pumpApp(tester, feed: [for (var i = 0; i < 30; i++) 'p$i']);
    await tester.pumpAndSettle();
    final list = find.descendant(
      of: find.byType(CustomScrollView),
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(list.first).position;
    position.jumpTo(2500);
    await tester.pumpAndSettle();
    final offset = position.pixels;

    app.client.setHandler(
        'GET',
        'feed',
        (_) => {
              'items': [
                _post('fresh'),
                for (var i = 0; i < 29; i++) _post('p$i'),
              ],
              'next_cursor': null,
              'limit': 30,
            });
    app.awayFor(const Duration(minutes: 10));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('feed-new-posts')), findsOneWidget);
    expect(position.pixels, offset);

    // Back on the Feed root asks before leaving, whatever the list shows.
    await app.back();
    expect(find.text(_exitHint), findsOneWidget);
    expect(app.exits, 0);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('feed-new-posts')));
    await tester.pumpAndSettle();
    expect(position.pixels, 0);
    expect(find.text('Story fresh'), findsOneWidget);
  });
}
