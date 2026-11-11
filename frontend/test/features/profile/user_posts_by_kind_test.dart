import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';
import 'package:mushukistan_frontend/features/auth/application/auth_controller.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_models.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_repository.dart';
import 'package:mushukistan_frontend/features/profile/presentation/screens/user_activity_screen.dart';

import '../../support/fakes.dart';

Map<String, Object?> _post(String id, String kind) => {
      'id': id,
      'cat': {'id': 'cat-$id', 'status': 'unknown', 'name': 'Cat $id'},
      'author': {'id': 'user-1', 'name': 'Author'},
      'photo_url': 'https://example.com/$id.jpg',
      'photo_urls': ['https://example.com/$id.jpg'],
      'description': 'Post $id',
      'location': null,
      'kind': kind,
      'created_at': '2026-10-01T00:00:00Z',
      'like_count': 0,
      'comment_count': 0,
      'is_liked_by_me': false,
    };

Future<void> _mount(
  WidgetTester tester,
  FakeApiClient client, {
  String? kind,
}) async {
  final container = ProviderContainer(overrides: [
    mushukistanApiProvider.overrideWithValue(MushukistanApi(client: client)),
    authRepositoryProvider.overrideWithValue(FakeAuthRepository(
      restoreResult: SessionRestoreSuccess(
        AuthSession.restored(accessToken: 'token', user: testUser()),
      ),
    )),
    googleIdentityTokenProvider.overrideWithValue(
      FakeGoogleIdentityTokenProvider(),
    ),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: UserPostsScreen(userId: 'user-1', isCurrentUser: true, kind: kind),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('cat posts list asks the API for observation posts only',
      (tester) async {
    final client = FakeApiClient()
      ..setHandler('GET', 'users/user-1/posts', (call) {
        return {
          'items': [_post('a', 'observation')],
          'limit': 50,
        };
      });
    await _mount(tester, client, kind: 'observation');

    expect(find.text('My cat posts'), findsOneWidget);
    expect(client.calls, isNotEmpty);
    expect(
        client.calls.every((c) => c.queryParameters?['kind'] == 'observation'),
        isTrue);
    expect(find.text('Load more posts'), findsNothing);
  });

  testWidgets('needs-help list shows its own title and empty state',
      (tester) async {
    final client = FakeApiClient()
      ..setHandler('GET', 'users/user-1/posts',
          (_) => {'items': <Object>[], 'limit': 50});
    await _mount(tester, client, kind: 'needs_help');

    expect(find.text('My “Cat needs help” posts'), findsOneWidget);
    expect(find.text('No “Cat needs help” posts yet.'), findsOneWidget);
    expect(client.calls, isNotEmpty);
    expect(
        client.calls.every((c) => c.queryParameters?['kind'] == 'needs_help'),
        isTrue);
  });

  testWidgets('combined list sends no kind filter', (tester) async {
    final client = FakeApiClient()
      ..setHandler('GET', 'users/user-1/posts',
          (_) => {'items': <Object>[], 'limit': 50});
    await _mount(tester, client);

    expect(find.text('My posts'), findsOneWidget);
    expect(client.calls, isNotEmpty);
    expect(
        client.calls
            .any((c) => c.queryParameters?.containsKey('kind') ?? false),
        isFalse);
  });

  testWidgets('load more keeps the kind filter and skips duplicates',
      (tester) async {
    var failNext = false;
    final client = FakeApiClient()
      ..setHandler('GET', 'users/user-1/posts', (call) {
        final cursor = call.queryParameters?['cursor'];
        if (cursor == null) {
          return {
            'items': [_post('a', 'observation')],
            'limit': 50,
            'next_cursor': 'c1',
          };
        }
        if (failNext) {
          failNext = false;
          throw StateError('network down');
        }
        return {
          'items': [_post('a', 'observation'), _post('b', 'observation')],
          'limit': 50,
        };
      });
    await _mount(tester, client, kind: 'observation');

    expect(find.text('Post a'), findsOneWidget);
    expect(find.text('Post b'), findsNothing);

    failNext = true;
    await tester.scrollUntilVisible(find.text('Load more posts'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text('Load more posts'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Load more posts'));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Post b'), findsNothing);

    await tester.ensureVisible(find.text('Retry'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    final pageCalls = client.calls
        .where((call) => call.queryParameters?['cursor'] == 'c1')
        .toList();
    expect(pageCalls, hasLength(2));
    expect(pageCalls.every((c) => c.queryParameters?['kind'] == 'observation'),
        isTrue);
    await tester.scrollUntilVisible(find.text('Post b'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Post b'), findsOneWidget);
    expect(find.text('Post a', skipOffstage: false), findsOneWidget);
    expect(find.text('Load more posts'), findsNothing);
    expect(find.text('Retry'), findsNothing);
  });
}
