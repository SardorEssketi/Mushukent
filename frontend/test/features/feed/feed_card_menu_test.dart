// The "more" menu at the top right of a feed card offers the same actions as
// the publication's detail screen.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';
import 'package:mushukistan_frontend/features/auth/application/auth_controller.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_models.dart';
import 'package:mushukistan_frontend/features/feed/presentation/widgets/feed_card_menu.dart';
import 'package:mushukistan_frontend/features/posts/application/saved_posts.dart';

import '../../support/fakes.dart';

const _ownerId = '11111111-1111-4111-8111-111111111111';
const _otherId = '22222222-2222-4222-8222-222222222222';

PostSummary _post({
  String authorId = _ownerId,
  String kind = 'observation',
  bool saved = false,
}) =>
    PostSummary.fromJson({
      'id': 'post-1',
      'kind': kind,
      'is_saved_by_me': saved,
      'cat': {'id': 'cat-1', 'name': 'Ryzhik'},
      'author': {'id': authorId, 'name': 'Author'},
      'photo_url': 'https://example.com/p.jpg',
      'created_at': '2026-11-09T10:00:00Z',
    });

LostPetData _lostPet({String authorId = _ownerId}) => LostPetData.fromJson({
      'id': 'lost-1',
      'item_type': 'lost_pet',
      'pet_name': 'Qoravoy',
      'author': {'id': authorId, 'name': 'Author'},
      'photo_url': 'https://example.com/p.jpg',
      'photo_urls': ['https://example.com/p.jpg'],
      'created_at': '2026-11-09T10:00:00Z',
    });

Future<(FakeApiClient, GoRouter)> _pump(
  WidgetTester tester,
  FeedItem item, {
  MushukistanUser? viewer,
}) async {
  final client = FakeApiClient()
    ..setHandler('DELETE', 'posts/post-1', (_) => null)
    ..setHandler('POST', 'posts/post-1/saved', (_) => null)
    ..setHandler('DELETE', 'posts/post-1/saved', (_) => null)
    ..setHandler('DELETE', 'lost-pets/lost-1', (_) => null);
  final router = GoRouter(routes: [
    GoRoute(
      path: '/',
      builder: (_, __) => Scaffold(
        body: Align(
          alignment: Alignment.topRight,
          child: FeedCardMenu(item: item),
        ),
      ),
    ),
    GoRoute(path: '/report', builder: (_, s) => Text('Report ${s.uri}')),
    GoRoute(
        path: '/posts/:id/edit',
        builder: (_, s) => Text('Edit post ${s.pathParameters['id']}')),
    GoRoute(
        path: '/lost-pets/:id/edit',
        builder: (_, s) => Text('Edit lost ${s.pathParameters['id']}')),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      mushukistanApiProvider.overrideWithValue(MushukistanApi(client: client)),
      currentUserProvider.overrideWithValue(viewer),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return (client, router);
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Post actions'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('owner can edit and delete their post from the card',
      (tester) async {
    final (client, _) = await _pump(tester, _post(), viewer: testUser());
    await _open(tester);
    expect(find.text('Edit post'), findsOneWidget);
    expect(find.text('Delete post'), findsOneWidget);
    expect(find.text('Report'), findsNothing);

    await tester.tap(find.text('Delete post'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(
        client.calls
            .where((c) => c.method == 'DELETE' && c.path == 'posts/post-1'),
        hasLength(1));
    expect(find.text('Post deleted'), findsOneWidget);
  });

  testWidgets('edit opens the edit screen', (tester) async {
    await _pump(tester, _lostPet(), viewer: testUser());
    await _open(tester);
    await tester.tap(find.text('Edit lost pet'));
    await tester.pumpAndSettle();
    expect(find.text('Edit lost lost-1'), findsOneWidget);
  });

  testWidgets('other users can only report', (tester) async {
    await _pump(tester, _post(authorId: _otherId), viewer: testUser());
    await _open(tester);
    expect(find.text('Report'), findsOneWidget);
    expect(find.text('Edit post'), findsNothing);
    expect(find.text('Delete post'), findsNothing);
    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();
    expect(find.textContaining('type=post'), findsOneWidget);
    expect(find.textContaining('id=post-1'), findsOneWidget);
  });

  testWidgets('moderators can also remove other users\' posts', (tester) async {
    final (client, _) = await _pump(tester, _lostPet(authorId: _otherId),
        viewer: testUser(isModerator: true));
    await _open(tester);
    expect(find.text('Report'), findsOneWidget);
    await tester.tap(find.text('Remove as moderator'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(
        client.calls.where((c) => c.path == 'lost-pets/lost-1'), hasLength(1));
  });

  testWidgets('cat posts of other users can be saved and removed',
      (tester) async {
    final (client, _) =
        await _pump(tester, _post(authorId: _otherId), viewer: testUser());
    await _open(tester);
    expect(find.text('Save'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
        client.calls
            .where((c) => c.method == 'POST' && c.path == 'posts/post-1/saved'),
        hasLength(1));
    expect(find.text('Added to saved posts'), findsOneWidget);

    await _open(tester);
    expect(find.text('Save'), findsNothing);
    await tester.tap(find.text('Remove from saved'));
    await tester.pumpAndSettle();
    expect(
        client.calls.where(
            (c) => c.method == 'DELETE' && c.path == 'posts/post-1/saved'),
        hasLength(1));
    expect(find.text('Removed from saved posts'), findsOneWidget);
  });

  testWidgets('an already saved post offers Remove from saved', (tester) async {
    await _pump(tester, _post(authorId: _otherId, saved: true),
        viewer: testUser());
    await _open(tester);
    expect(find.text('Remove from saved'), findsOneWidget);
    expect(find.text('Save'), findsNothing);
  });

  testWidgets('Save is not offered on own, Needs help or signed-out views',
      (tester) async {
    await _pump(tester, _post(), viewer: testUser());
    await _open(tester);
    expect(find.text('Save'), findsNothing);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    await _pump(tester, _post(authorId: _otherId, kind: 'needs_help'),
        viewer: testUser());
    await _open(tester);
    expect(find.text('Save'), findsNothing);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    await _pump(tester, _post(authorId: _otherId), viewer: null);
    await _open(tester);
    expect(find.text('Save'), findsNothing);
    expect(find.text('Report'), findsOneWidget);
  });

  test('private posts (moderator view) are not offered for saving', () {
    final private = PostDetail.fromJson({
      'id': 'p',
      'kind': 'observation',
      'is_public': false,
      'cat': {'id': 'c'},
      'author': {'id': _otherId},
      'photo_url': 'x',
      'created_at': '2026-11-09T10:00:00Z',
    });
    expect(canSavePost(private, testUser(isModerator: true)), isFalse);
    final public = PostDetail.fromJson({
      'id': 'p',
      'kind': 'observation',
      'is_public': true,
      'cat': {'id': 'c'},
      'author': {'id': _otherId},
      'photo_url': 'x',
      'created_at': '2026-11-09T10:00:00Z',
    });
    expect(canSavePost(public, testUser()), isTrue);
    expect(canSavePost(public, null), isFalse);
  });
}
