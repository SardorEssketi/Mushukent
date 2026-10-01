import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mushukistan_frontend/core/localization/language_controller.dart';
import 'package:mushukistan_frontend/core/network/api_error.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';
import 'package:mushukistan_frontend/features/auth/application/auth_controller.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_models.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_repository.dart';
import 'package:mushukistan_frontend/features/feed/presentation/screens/feed_screen.dart';
import 'package:mushukistan_frontend/features/feed/presentation/widgets/feed_card_parts.dart';

import '../../support/fakes.dart';

Map<String, Object?> _page(List<Object?> items, [String? cursor]) => {
      'items': items,
      'next_cursor': cursor,
      'limit': 30,
    };

Map<String, Object?> _observation(
  String id, {
  String kind = 'observation',
  String? name,
  String? description,
  List<String>? photos,
  String? avatarUrl,
}) =>
    {
      'item_type': 'observation',
      'id': id,
      'kind': kind,
      'cat': {'id': 'cat-$id', 'name': name ?? 'Cat $id', 'status': 'healthy'},
      'author': {
        'id': 'author-1',
        'name': 'Amina',
        'avatar_url': avatarUrl,
      },
      'photo_url': 'invalid:',
      'photo_urls': photos ?? ['invalid:'],
      'description': description,
      'created_at': '2026-09-01T10:00:00Z',
      'like_count': 3,
      'comment_count': 12,
      'is_liked_by_me': false,
    };

Map<String, Object?> _lost(String id) => {
      'item_type': 'lost_pet',
      'id': id,
      'pet_name': 'Lost Milo',
      'owner_phone_number': '+998901234567',
      'photo_url': 'invalid:',
      'photo_urls': ['invalid:'],
      'last_seen_location': {'latitude': 41.3, 'longitude': 69.2},
      'additional_info': 'Last seen near the park',
      'is_resolved': false,
      'comment_count': 5,
      'created_at': '2026-09-01T10:00:00Z',
    };

Map<String, Object?> _adoption(String id) => {
      'item_type': 'adoption',
      'id': id,
      'pet_name': 'Rehome Luna',
      'owner_phone_number': '+998901234567',
      'photo_url': 'invalid:',
      'photo_urls': ['invalid:'],
      'additional_info': 'Friendly indoor cat',
      'is_resolved': false,
      'comment_count': 2,
      'created_at': '2026-09-01T10:00:00Z',
    };

void _size(WidgetTester tester, double width, double height) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpFeed(WidgetTester tester, FakeApiClient client) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      mushukistanApiProvider.overrideWithValue(MushukistanApi(client: client)),
    ],
    child: const MaterialApp(home: FeedScreen()),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('initial error retries without changing the selected mode',
      (tester) async {
    _size(tester, 800, 950);
    var requests = 0;
    final client = FakeApiClient();
    client.setHandler('GET', 'feed', (_) {
      requests++;
      if (requests == 1) {
        throw const MushukistanApiException(
          kind: ApiFailureKind.network,
          code: 'NETWORK_ERROR',
          message: 'Offline',
        );
      }
      return _page([_observation('recovered')]);
    });
    await _pumpFeed(tester, client);
    expect(find.text('Could not load this section'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(requests, 2);
    expect(find.text('Cat recovered'), findsOneWidget);
  });

  testWidgets('mixed Recent uses shared cards and kind-specific actions',
      (tester) async {
    _size(tester, 800, 1200);
    final client = FakeApiClient();
    client.setHandler(
        'GET',
        'feed',
        (_) => _page([
              _observation('one', name: 'Milo'),
              _observation('help', kind: 'needs_help', name: 'Tiger'),
              _lost('lost'),
              _adoption('adopt'),
            ]));
    await _pumpFeed(tester, client);

    expect(find.text('Milo'), findsOneWidget);
    expect(find.text('Needs help'), findsWidgets);
    expect(find.byType(FeedPostCard), findsWidgets);
    expect(find.byIcon(Icons.favorite_outline), findsWidgets);
    await tester.scrollUntilVisible(find.text('Lost Milo'), 350,
        scrollable: find
            .descendant(
                of: find.byType(CustomScrollView),
                matching: find.byType(Scrollable))
            .first);
    expect(find.text('Lost Pet'), findsOneWidget);
    expect(find.text('View on map'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Rehome Luna'), 350,
        scrollable: find
            .descendant(
                of: find.byType(CustomScrollView),
                matching: find.byType(Scrollable))
            .first);
    expect(find.text('Adoption'), findsWidgets);
    expect(find.byType(FeedKindBadge), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('filter and Popular period start new first-page queries',
      (tester) async {
    _size(tester, 850, 950);
    final client = FakeApiClient();
    client.setHandler('GET', 'feed', (_) => _page([]));
    client.setHandler('GET', 'lost-pets', (_) => _page([_lost('lost')]));
    client.setHandler(
        'GET', 'adoption-posts', (_) => _page([_adoption('adopt')]));
    await _pumpFeed(tester, client);
    expect(client.calls.last.queryParameters?['filter'], 'recent');
    expect(find.text('Today'), findsNothing);
    expect(find.text('No observations yet.'), findsOneWidget);

    await tester.tap(find.text('Popular'));
    await tester.pumpAndSettle();
    expect(find.text('Today'), findsOneWidget);
    expect(client.calls.last.queryParameters?['filter'], 'popular');
    expect(client.calls.last.queryParameters?['popular_period'], 'day');
    await tester.tap(find.text('Month'));
    await tester.pumpAndSettle();
    expect(client.calls.last.queryParameters?['popular_period'], 'month');
    expect(client.calls.last.queryParameters?.containsKey('cursor'), isFalse);

    await tester.tap(find.text('Lost pets'));
    await tester.pumpAndSettle();
    expect(client.calls.last.path, 'lost-pets');
    expect(find.text('Today'), findsNothing);
    await tester.tap(find.text('Adoption').first);
    await tester.pumpAndSettle();
    expect(client.calls.last.path, 'adoption-posts');
  });

  testWidgets('cursor pages append, deduplicate, and stop at null cursor',
      (tester) async {
    _size(tester, 800, 950);
    final client = FakeApiClient();
    client.setHandler('GET', 'feed', (call) {
      if (call.queryParameters?['cursor'] == 'next') {
        return _page([_observation('one'), _observation('two')]);
      }
      return _page([_observation('one')], 'next');
    });
    await _pumpFeed(tester, client);
    expect(client.calls.where((call) => call.path == 'feed').length, 2);
    await tester.scrollUntilVisible(find.text('Cat two'), 250,
        scrollable: find
            .descendant(
                of: find.byType(CustomScrollView),
                matching: find.byType(Scrollable))
            .first);
    expect(find.text('Cat two'), findsOneWidget);
    expect(find.byType(FeedPostCard), findsNWidgets(2));
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(client.calls.where((call) => call.path == 'feed').length, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('next-page error preserves posts and Retry loads the page',
      (tester) async {
    _size(tester, 800, 950);
    var attempts = 0;
    final client = FakeApiClient();
    client.setHandler('GET', 'feed', (call) {
      if (call.queryParameters?['cursor'] == 'next') {
        attempts++;
        if (attempts == 1) {
          throw const MushukistanApiException(
            kind: ApiFailureKind.network,
            code: 'NETWORK_ERROR',
            message: 'Offline',
          );
        }
        return _page([_observation('two')]);
      }
      return _page([_observation('one')], 'next');
    });
    await _pumpFeed(tester, client);
    expect(find.text('Cat one'), findsOneWidget);
    expect(find.text('Could not load this section'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.text('Cat two'), findsOneWidget);
  });

  testWidgets('refresh replaces loaded pages and resets the cursor',
      (tester) async {
    _size(tester, 800, 950);
    var firstLoads = 0;
    final client = FakeApiClient();
    client.setHandler('GET', 'feed', (call) {
      if (call.queryParameters?['cursor'] == 'next') {
        return _page([_observation('old-two')]);
      }
      firstLoads++;
      return firstLoads == 1
          ? _page([_observation('old-one')], 'next')
          : _page([_observation('new-one')]);
    });
    await _pumpFeed(tester, client);
    expect(client.calls.length, 2);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 550));
    await tester.pumpAndSettle();
    expect(firstLoads, 2);
    expect(find.text('Cat new-one'), findsOneWidget);
    expect(find.text('Cat old-one'), findsNothing);
    expect(find.text('Cat old-two'), findsNothing);
    expect(client.calls.length, 3);
  });

  testWidgets('changing filters discards pages from the old query',
      (tester) async {
    _size(tester, 800, 950);
    final client = FakeApiClient();
    client.setHandler('GET', 'feed', (call) {
      if (call.queryParameters?['filter'] == 'popular') {
        return _page([_observation('popular')]);
      }
      if (call.queryParameters?['cursor'] == 'next') {
        return _page([_observation('old-second')]);
      }
      return _page([_observation('old-first')], 'next');
    });
    await _pumpFeed(tester, client);
    expect(client.calls.length, 2);
    await tester.tap(find.text('Popular'));
    await tester.pumpAndSettle();
    expect(find.text('Cat popular'), findsOneWidget);
    expect(find.text('Cat old-first'), findsNothing);
    expect(find.text('Cat old-second'), findsNothing);
    expect(client.calls.last.queryParameters?['cursor'], isNull);
  });

  testWidgets('Lost Pet and Adoption lists use their own cursors',
      (tester) async {
    _size(tester, 800, 950);
    final client = FakeApiClient();
    client.setHandler('GET', 'feed', (_) => _page([]));
    client.setHandler(
        'GET',
        'lost-pets',
        (call) => call.queryParameters?['cursor'] == 'lost-next'
            ? _page([_lost('lost-two')])
            : _page([_lost('lost-one')], 'lost-next'));
    client.setHandler(
        'GET',
        'adoption-posts',
        (call) => call.queryParameters?['cursor'] == 'adoption-next'
            ? _page([_adoption('adopt-two')])
            : _page([_adoption('adopt-one')], 'adoption-next'));
    await _pumpFeed(tester, client);
    await tester.tap(find.text('Lost pets'));
    await tester.pumpAndSettle();
    expect(
        client.calls
            .where((call) =>
                call.path == 'lost-pets' &&
                call.queryParameters?['cursor'] == 'lost-next')
            .length,
        1);
    await tester.tap(find.text('Adoption').first);
    await tester.pumpAndSettle();
    expect(
        client.calls
            .where((call) =>
                call.path == 'adoption-posts' &&
                call.queryParameters?['cursor'] == 'adoption-next')
            .length,
        1);
  });

  testWidgets('gallery, long text, and broken avatar work at compact width',
      (tester) async {
    _size(tester, 360, 800);
    final client = FakeApiClient();
    client.setHandler(
        'GET',
        'feed',
        (_) => _page([
              _observation('one',
                  avatarUrl: 'invalid:',
                  photos: ['invalid:first', 'invalid:second'],
                  description: 'A long description of a spotted cat. ' * 12),
            ]));
    await _pumpFeed(tester, client);
    expect(find.text('A'), findsOneWidget);
    expect(find.text('1/2'), findsOneWidget);
    expect(find.text('Read more'), findsOneWidget);
    await tester.tap(find.byTooltip('Next photo'));
    await tester.pumpAndSettle();
    expect(find.text('2/2'), findsOneWidget);
    await tester.tap(find.text('Read more'));
    await tester.pumpAndSettle();
    expect(find.text('Show less'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('guest like opens authentication gate and author opens profile',
      (tester) async {
    _size(tester, 800, 950);
    final client = FakeApiClient();
    client.setHandler('GET', 'feed', (_) => _page([_observation('one')]));
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const FeedScreen(),
        routes: [
          GoRoute(
              path: 'auth-required',
              builder: (_, __) => const Scaffold(body: Text('Auth gate'))),
          GoRoute(
              path: 'users/:id',
              builder: (_, __) => const Scaffold(body: Text('Author profile'))),
        ],
      ),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        mushukistanApiProvider
            .overrideWithValue(MushukistanApi(client: client)),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.favorite_outline));
    await tester.pumpAndSettle();
    expect(find.text('Auth gate'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Amina'));
    await tester.pumpAndSettle();
    expect(find.text('Author profile'), findsOneWidget);
  });

  testWidgets('comments and each card kind open their matching detail route',
      (tester) async {
    _size(tester, 800, 1000);
    final client = FakeApiClient();
    client.setHandler(
        'GET',
        'feed',
        (_) => _page([
              _observation('one'),
              _lost('lost'),
              _adoption('adopt'),
            ]));
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const FeedScreen()),
      GoRoute(
          path: '/posts/:id',
          builder: (_, __) => const Scaffold(body: Text('Observation detail'))),
      GoRoute(
          path: '/lost-pets/:id',
          builder: (_, __) => const Scaffold(body: Text('Lost detail'))),
      GoRoute(
          path: '/adoption-posts/:id',
          builder: (_, __) => const Scaffold(body: Text('Rehoming detail'))),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        mushukistanApiProvider
            .overrideWithValue(MushukistanApi(client: client)),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Comments').first);
    await tester.pumpAndSettle();
    expect(find.text('Observation detail'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();

    final scrolling = find
        .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable))
        .first;
    await tester.scrollUntilVisible(find.text('Lost Milo'), 350,
        scrollable: scrolling);
    await tester.ensureVisible(find.text('Lost Milo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lost Milo'));
    await tester.pumpAndSettle();
    expect(find.text('Lost detail'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Rehome Luna'), 350,
        scrollable: scrolling);
    await tester.ensureVisible(find.text('Rehome Luna'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rehome Luna'));
    await tester.pumpAndSettle();
    expect(find.text('Rehoming detail'), findsOneWidget);
  });

  testWidgets(
      'authenticated likes update optimistically and failed unlike rolls back',
      (tester) async {
    _size(tester, 800, 950);
    final pendingLike = Completer<Object?>();
    final client = FakeApiClient();
    client.setHandler('GET', 'feed', (_) => _page([_observation('one')]));
    client.setHandler('POST', 'posts/one/likes', (_) => pendingLike.future);
    client.setHandler('DELETE', 'posts/one/likes', (_) {
      throw const MushukistanApiException(
        kind: ApiFailureKind.network,
        code: 'NETWORK_ERROR',
        message: 'Offline',
      );
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [
        mushukistanApiProvider
            .overrideWithValue(MushukistanApi(client: client)),
        authRepositoryProvider.overrideWithValue(FakeAuthRepository(
          restoreResult: SessionRestoreSuccess(AuthSession.restored(
            accessToken: 'test-token',
            user: testUser(),
          )),
        )),
        googleIdentityTokenProvider.overrideWithValue(
          FakeGoogleIdentityTokenProvider(),
        ),
      ],
      child: const MaterialApp(home: FeedScreen()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.favorite_outline));
    await tester.pump();
    expect(find.byIcon(Icons.favorite), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.favorite));
    expect(client.calls.where((call) => call.method == 'POST').length, 1);
    pendingLike.complete({'liked': true, 'like_count': 4});
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.favorite));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.favorite), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(client.calls.where((call) => call.method == 'DELETE').length, 1);
  });

  testWidgets('media stays bounded and translated filters do not overflow',
      (tester) async {
    _size(tester, 360, 900);
    final client = FakeApiClient();
    client.setHandler(
        'GET',
        'feed',
        (_) => _page([
              _observation('one',
                  name: 'A very long name for a community cat',
                  description: 'A detailed observation. ' * 8),
            ]));
    for (final (width, language) in [
      (360.0, AppLanguage.english),
      (800.0, AppLanguage.russian),
      (1280.0, AppLanguage.uzbek),
      (1700.0, AppLanguage.english),
    ]) {
      tester.view.physicalSize = Size(width, 900);
      await tester.pumpWidget(ProviderScope(
        key: ValueKey('$width-${language.code}'),
        overrides: [
          mushukistanApiProvider.overrideWithValue(
            MushukistanApi(client: client),
          ),
          appLanguageProvider.overrideWith((ref) => language),
        ],
        child: const MaterialApp(home: FeedScreen()),
      ));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byKey(const ValueKey('feed-media'))).height,
          lessThanOrEqualTo(420));
      expect(tester.takeException(), isNull);
    }
  });
}
