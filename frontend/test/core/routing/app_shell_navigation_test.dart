import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mushukistan_frontend/core/navigation/settings_changes_guard.dart';
import 'package:mushukistan_frontend/core/navigation/tab_actions.dart';
import 'package:mushukistan_frontend/core/network/api_client.dart';
import 'package:mushukistan_frontend/core/widgets/app_shell_scaffold.dart';
import 'package:mushukistan_frontend/features/auth/application/auth_controller.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_repository.dart';
import 'package:mushukistan_frontend/features/feed/presentation/screens/feed_screen.dart';

import '../../support/fakes.dart';

Map<String, Object?> _feedResponse() => {
      'items': List.generate(
          16,
          (index) => {
                'id': 'post-$index',
                'cat': {'id': 'cat-$index', 'name': 'Milo $index'},
                'author': {'id': 'author', 'name': 'Amina'},
                'photo_url': 'invalid:',
                'photo_urls': <Object?>[],
                'description': 'A neighborhood cat update',
                'created_at': '2026-09-01T10:00:00Z',
                'like_count': 0,
                'comment_count': 0,
                'is_liked_by_me': false,
              }),
      'next_cursor': null,
      'limit': 30,
    };

Future<(ProviderContainer, GoRouter)> _mount(
  WidgetTester tester, {
  String initialLocation = '/feed',
}) async {
  final apiClient = FakeApiClient()
    ..setHandler('GET', 'feed', (_) => _feedResponse());
  final container = ProviderContainer(overrides: [
    apiClientProvider.overrideWithValue(apiClient),
    authRepositoryProvider.overrideWithValue(
      FakeAuthRepository(restoreResult: const SessionRestoreMissing()),
    ),
    googleIdentityTokenProvider.overrideWithValue(
      FakeGoogleIdentityTokenProvider(),
    ),
  ]);
  await container.read(authControllerProvider.notifier).restoreSession();

  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShellScaffold(
          navigationShell: shell,
          location: state.uri.path,
        ),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/feed', builder: (_, __) => const FeedScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/map',
              builder: (_, __) => const Scaffold(body: Text('Map root')),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/add',
              builder: (_, __) => const Scaffold(body: Text('Add root')),
              routes: [
                GoRoute(
                  path: 'inner',
                  builder: (_, __) => const Scaffold(body: Text('Add inner')),
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/leaderboards',
              builder: (_, __) => const Scaffold(body: Text('Leaders root')),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/profile',
              builder: (context, __) => Scaffold(
                body: Column(
                  children: [
                    const Text('Profile root'),
                    TextButton(
                      onPressed: () => context.push('/profile/edit'),
                      child: const Text('Open edit'),
                    ),
                  ],
                ),
              ),
              routes: [
                GoRoute(
                  path: 'edit',
                  builder: (_, __) =>
                      const Scaffold(body: Text('Edit profile')),
                ),
                GoRoute(
                  path: 'settings',
                  builder: (_, __) =>
                      const Scaffold(body: Text('Settings screen')),
                ),
              ],
            ),
          ]),
        ],
      ),
    ],
  );
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  addTearDown(container.dispose);
  addTearDown(router.dispose);
  return (container, router);
}

Finder _tab(String label) => find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text(label),
    );

void main() {
  testWidgets('Profile edit then Map then Profile returns to Profile root',
      (tester) async {
    final (_, router) = await _mount(tester, initialLocation: '/profile');
    await tester.tap(find.text('Open edit'));
    await tester.pumpAndSettle();
    expect(find.text('Edit profile'), findsOneWidget);

    await tester.tap(_tab('Map'));
    await tester.pumpAndSettle();
    expect(find.text('Map root'), findsOneWidget);
    await tester.tap(_tab('Profile'));
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/profile');
    expect(find.text('Profile root'), findsOneWidget);
    expect(find.text('Edit profile'), findsNothing);
  });

  testWidgets('Add inner route hides navigation and Add returns to its root',
      (tester) async {
    final (_, router) = await _mount(tester, initialLocation: '/add/inner');
    expect(find.text('Add inner'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    router.go('/map');
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    await tester.tap(_tab('Add'));
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/add');
    expect(find.text('Add root'), findsOneWidget);
    expect(find.text('Add inner'), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('Feed Map Feed reuses the root without losing scroll position',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final (container, router) = await _mount(tester);
    final feedState = tester.state(find.byType(FeedScreen));
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -1000));
    await tester.pumpAndSettle();
    final scrollController = tester
        .widget<CustomScrollView>(find.byType(CustomScrollView))
        .controller!;
    final scrollOffset = scrollController.offset;
    expect(scrollOffset, greaterThan(0));

    await tester.tap(_tab('Map'));
    await tester.pumpAndSettle();
    await tester.tap(_tab('Feed'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/feed');
    expect(tester.state(find.byType(FeedScreen)), same(feedState));
    expect(scrollController.offset, scrollOffset);
    expect(container.read(feedScrollToTopRequestsProvider), 0);

    await tester.tap(_tab('Feed'));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expect(scrollController.offset, 0);
    expect(find.byType(FeedScreen), findsOneWidget);
  });

  testWidgets('tab switching respects dirty Edit Profile confirmation',
      (tester) async {
    final (container, router) = await _mount(
      tester,
      initialLocation: '/profile/edit',
    );
    container.read(editProfileHasUnsavedChangesProvider.notifier).state = true;
    await tester.tap(_tab('Map'));
    await tester.pumpAndSettle();
    expect(find.text('Unsaved changes'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/profile/edit');

    await tester.tap(_tab('Map'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard changes'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/map');
  });

  testWidgets('tab switching still respects dirty Settings confirmation',
      (tester) async {
    final (container, router) = await _mount(
      tester,
      initialLocation: '/profile/settings',
    );
    var discarded = false;
    container.read(settingsHasUnsavedChangesProvider.notifier).state = true;
    container.read(settingsDiscardChangesProvider.notifier).state = () {
      discarded = true;
    };

    await tester.tap(_tab('Map'));
    await tester.pumpAndSettle();
    expect(find.text('Unsaved changes'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/profile/settings');

    await tester.tap(_tab('Map'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard changes'));
    await tester.pumpAndSettle();
    expect(discarded, isTrue);
    expect(router.routeInformationProvider.value.uri.path, '/map');
  });
}
