// Profile → Saved posts lists the viewer's saved cat posts.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';
import 'package:mushukistan_frontend/features/auth/application/auth_controller.dart';
import 'package:mushukistan_frontend/features/profile/presentation/screens/saved_posts_screen.dart';

import '../../support/fakes.dart';

Map<String, Object?> _post(String id) => {
      'id': id,
      'kind': 'observation',
      'is_saved_by_me': true,
      'cat': {'id': 'cat-$id', 'name': 'Cat $id'},
      'author': {'id': 'author-1', 'name': 'Amina'},
      'photo_url': 'invalid:',
      'photo_urls': ['invalid:'],
      'description': 'Saved $id',
      'created_at': '2026-11-09T10:00:00Z',
    };

Future<FakeApiClient> _pump(WidgetTester tester, List<String> ids,
    {bool moderator = false}) async {
  tester.view.physicalSize = const Size(420, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final client = FakeApiClient()
    ..setHandler(
        'GET',
        'users/me/saved-posts',
        (_) => {
              'items': [for (final id in ids) _post(id)],
              'limit': 50
            })
    ..setHandler('DELETE', 'posts/a/saved', (_) => null)
    ..setHandler('DELETE', 'moderation/posts/a', (_) => null);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      mushukistanApiProvider.overrideWithValue(MushukistanApi(client: client)),
      currentUserProvider.overrideWithValue(testUser(isModerator: moderator)),
    ],
    child: const MaterialApp(home: SavedPostsScreen()),
  ));
  await tester.pumpAndSettle();
  return client;
}

void main() {
  testWidgets('lists saved posts', (tester) async {
    final client = await _pump(tester, ['a', 'b']);
    expect(find.text('Saved posts'), findsOneWidget);
    expect(find.text('Cat a'), findsOneWidget);
    expect(find.text('Cat b'), findsOneWidget);
    expect(client.calls.single.path, 'users/me/saved-posts');
  });

  testWidgets('removing from saved hides the post at once', (tester) async {
    await _pump(tester, ['a', 'b']);
    await tester
        .tap(find.byKey(const ValueKey('feed-card-menu:observation:a')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove from saved'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Cat a'), findsNothing);
    expect(find.text('Cat b'), findsOneWidget);
  });

  testWidgets('empty list explains how to save', (tester) async {
    await _pump(tester, []);
    expect(find.byKey(const ValueKey('saved-posts-empty')), findsOneWidget);
    expect(find.textContaining('Choose Save'), findsOneWidget);
  });

  testWidgets('a post a moderator removes disappears from the list',
      (tester) async {
    final client = await _pump(tester, ['a', 'b'], moderator: true);
    await tester
        .tap(find.byKey(const ValueKey('feed-card-menu:observation:a')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove as moderator'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(client.calls.where((c) => c.path == 'moderation/posts/a'),
        hasLength(1));
    expect(find.text('Cat a'), findsNothing);
    expect(find.text('Cat b'), findsOneWidget);
  });
}
