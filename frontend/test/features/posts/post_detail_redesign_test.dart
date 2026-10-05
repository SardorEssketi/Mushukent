import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';
import 'package:mushukistan_frontend/features/auth/application/auth_controller.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_models.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_repository.dart';
import 'package:mushukistan_frontend/features/posts/presentation/screens/post_detail_screen.dart';

import '../../support/fakes.dart';

final _owner = MushukistanUser(
  id: 'owner-1',
  registeredAt: DateTime.utc(2026, 1, 1),
);

Map<String, Object?> _post({
  String kind = 'observation',
  String? name,
  bool located = false,
}) =>
    {
      'id': 'post-1',
      'cat': {'id': 'cat-1', 'status': 'unknown', 'name': name},
      'author': {'id': 'owner-1', 'name': 'Amina'},
      'photo_url': 'https://example.com/cat.jpg',
      'photo_urls': ['https://example.com/cat.jpg'],
      'location': located ? {'latitude': 41.31, 'longitude': 69.28} : null,
      'description': kind == 'needs_help' ? 'Injured paw' : null,
      'kind': kind,
      'created_at': '2026-10-01T00:00:00Z',
      'like_count': 3,
      'comment_count': 2,
      'is_liked_by_me': false,
    };

Future<(FakeApiClient, GoRouter)> _mount(
  WidgetTester tester, {
  String kind = 'observation',
  String? name,
  bool located = false,
  bool moderator = false,
}) async {
  final client = FakeApiClient();
  client.setHandler('GET', 'posts/post-1',
      (_) => _post(kind: kind, name: name, located: located));
  client.setHandler('GET', 'posts/post-1/comments',
      (_) => {'items': <Object>[], 'next_cursor': null, 'limit': 20});
  client.setHandler(
      'POST', 'posts/post-1/likes', (_) => {'liked': true, 'like_count': 4});
  client.setHandler('DELETE', 'posts/post-1', (_) => null);
  client.setHandler('DELETE', 'moderation/posts/post-1', (_) => null);
  final user = MushukistanUser(
    id: moderator ? 'moderator-1' : _owner.id,
    registeredAt: _owner.registeredAt,
    isModerator: moderator,
  );
  final router = GoRouter(initialLocation: '/feed', routes: [
    GoRoute(
      path: '/feed',
      builder: (_, __) => const Scaffold(body: Text('Feed destination')),
    ),
    GoRoute(
      path: '/posts/:id',
      builder: (_, __) => const PostDetailScreen(postId: 'post-1'),
    ),
    GoRoute(
      path: '/posts/:id/edit',
      builder: (_, __) => const Scaffold(body: Text('Edit destination')),
    ),
    GoRoute(
      path: '/moderation/posts/:id/history',
      builder: (_, __) => const Scaffold(body: Text('History destination')),
    ),
    GoRoute(
      path: '/map',
      builder: (_, __) => const Scaffold(body: Text('Map destination')),
    ),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      mushukistanApiProvider.overrideWithValue(MushukistanApi(client: client)),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(
        restoreResult: SessionRestoreSuccess(
          AuthSession(accessToken: 'test-token', user: user),
        ),
      )),
      googleIdentityTokenProvider
          .overrideWithValue(FakeGoogleIdentityTokenProvider()),
      currentUserProvider.overrideWith((ref) => user),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  router.push('/posts/post-1');
  await tester.pumpAndSettle();
  return (client, router);
}

void main() {
  testWidgets('unnamed Cat post has natural title and no map action',
      (tester) async {
    await _mount(tester);
    expect(find.text('Cat post'), findsWidgets);
    expect(find.text('Unnamed cat'), findsNothing);
    expect(find.text('View on map'), findsNothing);
    expect(find.text('Likes'), findsNothing);
    await tester.scrollUntilVisible(find.text('Comments 2'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Comments 2'), findsOneWidget);
    expect(find.text('Edit post'), findsOneWidget);
  });

  testWidgets('help post shows badge, help section and location action',
      (tester) async {
    final (client, _) = await _mount(tester,
        kind: 'needs_help', located: true, moderator: true);
    expect(find.text('Cat needs help'), findsWidgets);
    expect(find.text('What help is needed'), findsOneWidget);
    expect(find.text('Injured paw'), findsOneWidget);
    expect(find.text('View on map'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Post history'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Post history'), findsOneWidget);
    expect(find.text('Remove as moderator'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Like 3'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Like 3'));
    await tester.pumpAndSettle();
    expect(
        client.calls.where((call) =>
            call.method == 'POST' && call.path == 'posts/post-1/likes'),
        hasLength(1));
  });

  testWidgets('owner deletion still calls the existing post endpoint',
      (tester) async {
    final (client, _) = await _mount(tester);
    await tester.scrollUntilVisible(find.text('Delete post'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Delete post'));
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(
        client.calls.where(
            (call) => call.method == 'DELETE' && call.path == 'posts/post-1'),
        hasLength(1));
    expect(find.text('Feed destination'), findsOneWidget);
  });

  testWidgets('moderator removal uses the moderation endpoint', (tester) async {
    final (client, _) = await _mount(tester, moderator: true);
    await tester.scrollUntilVisible(find.text('Remove as moderator'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Remove as moderator'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(
        client.calls.where((call) =>
            call.method == 'DELETE' && call.path == 'moderation/posts/post-1'),
        hasLength(1));
  });

  testWidgets('located post opens the Map from its location row',
      (tester) async {
    await _mount(tester, located: true);
    await tester.drag(find.byType(ListView).first, const Offset(0, -350));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View on map'));
    await tester.pumpAndSettle();
    expect(find.text('Map destination'), findsOneWidget);
  });
}
