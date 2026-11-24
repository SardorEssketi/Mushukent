import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';
import 'package:mushukistan_frontend/features/auth/application/auth_controller.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_models.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_repository.dart';
import 'package:mushukistan_frontend/features/profile/presentation/screens/my_activity_screen.dart';
import 'package:mushukistan_frontend/features/profile/presentation/screens/profile_screen.dart';

import '../../support/fakes.dart';

const _empty = {'items': <Object?>[], 'next_cursor': null, 'limit': 50};

Map<String, Object?> _post(String id, String kind) => {
      'id': id,
      'kind': kind,
      'cat': {'id': 'cat-$id', 'status': 'unknown', 'name': 'Cat $id'},
      'photo_url': 'invalid:',
      'photo_urls': ['invalid:'],
      'description': 'Post $id',
      'location': null,
      'created_at': '2026-11-01T00:00:00Z',
      'like_count': 0,
      'comment_count': 0,
      'author': {'id': testUser().id, 'name': 'Sardor'},
    };

class _Backend {
  final client = FakeApiClient();

  /// GET paths in the order they were requested.
  List<String> get loads => [
        for (final call in client.calls)
          if (call.method == 'GET') _label(call)
      ];

  static String _label(ApiCall call) => call.path.endsWith('/posts')
      ? 'posts:${call.queryParameters?['kind']}'
      : call.path;
}

Future<(_Backend, GoRouter)> _mount(WidgetTester tester,
    {String initialLocation = '/profile/activity'}) async {
  tester.view.physicalSize = const Size(800, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final backend = _Backend();
  backend.client
    ..setHandler('GET', 'users/${testUser().id}/posts', (call) {
      final kind = call.queryParameters?['kind'] as String?;
      return {
        'items': [
          for (var i = 0; i < 30; i++) _post('$kind-$i', kind ?? 'observation')
        ],
        'next_cursor': null,
        'limit': 50,
      };
    })
    ..setHandler('GET', 'lost-pets/mine', (_) => _empty)
    ..setHandler('GET', 'adoption-posts/mine', (_) => _empty);
  final container = ProviderContainer(overrides: [
    authRepositoryProvider.overrideWithValue(FakeAuthRepository(
      restoreResult: SessionRestoreSuccess(
        AuthSession.restored(accessToken: 'token', user: testUser()),
      ),
    )),
    googleIdentityTokenProvider
        .overrideWithValue(FakeGoogleIdentityTokenProvider()),
    mushukistanApiProvider
        .overrideWithValue(MushukistanApi(client: backend.client)),
    profileMeProvider.overrideWith((ref) async => UserProfileData(
          id: testUser().id,
          email: 'owner@example.com',
          registeredAt: DateTime.utc(2026, 7, 1),
          observationCount: 1,
          totalLikesReceived: 0,
          commentCount: 0,
          name: 'Sardor',
        )),
  ]);
  addTearDown(container.dispose);
  await container.read(authControllerProvider.notifier).restoreSession();
  // Same shape as the app: old routes redirect to the tab screen.
  final router = GoRouter(initialLocation: initialLocation, routes: [
    GoRoute(
      path: '/profile',
      builder: (_, __) => const ProfileScreen(),
      routes: [
        GoRoute(
          path: 'activity',
          builder: (_, state) => MyActivityScreen(
            initialTab:
                MyActivityTab.fromQuery(state.uri.queryParameters['tab']),
          ),
        ),
        for (final (path, tab) in [
          ('cat-posts', MyActivityTab.cats),
          ('needs-help-posts', MyActivityTab.needsHelp),
          ('lost-pets', MyActivityTab.lostPets),
          ('adoption-posts', MyActivityTab.rehoming),
        ])
          GoRoute(path: path, redirect: (_, __) => tab.location),
      ],
    ),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return (backend, router);
}

TabController _controller(WidgetTester tester) =>
    tester.widget<TabBar>(find.byType(TabBar)).controller!;

void main() {
  testWidgets('the profile row opens Your activities on the Cats tab',
      (tester) async {
    final (backend, _) = await _mount(tester, initialLocation: '/profile');
    await tester.tap(find.byKey(const ValueKey('profile-my-activity-row')));
    await tester.pumpAndSettle();
    expect(find.byType(MyActivityScreen), findsOneWidget);
    for (final label in ['Cats', 'Needs help', 'Lost', 'Rehoming']) {
      expect(find.widgetWithText(Tab, label), findsOneWidget);
    }
    expect(_controller(tester).index, 0);
    expect(find.text('Post observation-0'), findsOneWidget);
    expect(backend.loads, ['posts:observation']);
  });

  testWidgets('tabs switch lists and each loads only when first opened',
      (tester) async {
    final (backend, _) = await _mount(tester);
    expect(backend.loads, ['posts:observation']);

    await tester.tap(find.widgetWithText(Tab, 'Needs help'));
    await tester.pumpAndSettle();
    expect(find.text('Post needs_help-0'), findsOneWidget);
    expect(backend.loads, ['posts:observation', 'posts:needs_help']);

    await tester.tap(find.widgetWithText(Tab, 'Lost'));
    await tester.pumpAndSettle();
    expect(find.text('No lost pets yet.'), findsOneWidget);
    expect(backend.loads.last, 'lost-pets/mine');
    expect(backend.loads, isNot(contains('adoption-posts/mine')));

    await tester.tap(find.widgetWithText(Tab, 'Rehoming'));
    await tester.pumpAndSettle();
    expect(find.text('No rehoming posts yet.'), findsOneWidget);

    // Coming back does not load again: the tab kept its list.
    final loads = backend.loads.length;
    await tester.tap(find.widgetWithText(Tab, 'Cats'));
    await tester.pumpAndSettle();
    expect(find.text('Post observation-0'), findsOneWidget);
    expect(backend.loads.length, loads);
  });

  testWidgets('a tab keeps its scroll position', (tester) async {
    await _mount(tester);
    Finder catsList() => find
        .descendant(
            of: find.byKey(const ValueKey('my-activity-page-cats')),
            matching: find.byType(Scrollable))
        .first;
    await tester.drag(catsList(), const Offset(0, -1500));
    await tester.pumpAndSettle();
    final offset = tester.state<ScrollableState>(catsList()).position.pixels;
    expect(offset, greaterThan(500));

    await tester.tap(find.widgetWithText(Tab, 'Needs help'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(Tab, 'Cats'));
    await tester.pumpAndSettle();
    expect(tester.state<ScrollableState>(catsList()).position.pixels, offset);
  });

  testWidgets('pull to refresh reloads the open tab', (tester) async {
    final (backend, _) = await _mount(tester);
    await tester.fling(
        find.text('Post observation-0'), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(backend.loads, ['posts:observation', 'posts:observation']);
  });

  for (final (path, index, shown) in [
    ('/profile/cat-posts', 0, 'Post observation-0'),
    ('/profile/needs-help-posts', 1, 'Post needs_help-0'),
    ('/profile/lost-pets', 2, 'No lost pets yet.'),
    ('/profile/adoption-posts', 3, 'No rehoming posts yet.'),
    ('/profile/activity?tab=unknown', 0, 'Post observation-0'),
  ]) {
    testWidgets('$path opens tab $index', (tester) async {
      final (backend, router) = await _mount(tester, initialLocation: path);
      expect(find.byType(MyActivityScreen), findsOneWidget);
      expect(_controller(tester).index, index);
      expect(find.text(shown), findsOneWidget);
      // Only the opened tab loaded.
      expect(backend.loads, hasLength(1));
      if (index != 0 || path.contains('cat-posts')) {
        expect(router.routerDelegate.currentConfiguration.uri.path,
            '/profile/activity');
      }
    });
  }

  testWidgets('a post change reloads the opened tabs', (tester) async {
    final (backend, _) = await _mount(tester);
    await tester.tap(find.widgetWithText(Tab, 'Lost'));
    await tester.pumpAndSettle();
    final before = backend.loads.length;
    final container = ProviderScope.containerOf(
        tester.element(find.byType(MyActivityScreen)));
    container.read(postMutationRevisionProvider.notifier).state++;
    await tester.pumpAndSettle();
    final reloaded = backend.loads.sublist(before);
    expect(reloaded, containsAll(['posts:observation', 'lost-pets/mine']));
  });
}
