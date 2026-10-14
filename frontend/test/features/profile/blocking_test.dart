import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/core/network/api_client.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';
import 'package:mushukistan_frontend/features/profile/presentation/screens/blocked_users_screen.dart';

import '../../support/fakes.dart';

void main() {
  group('block data parsing', () {
    test('public profile reports the viewer relationship and defaults to false',
        () {
      final blocked = UserPublicData.fromJson({
        'id': 'u1',
        'registered_at': '2026-07-01T10:00:00Z',
        'is_blocked_by_viewer': true,
      });
      final legacy = UserPublicData.fromJson({
        'id': 'u2',
        'registered_at': '2026-07-01T10:00:00Z',
      });
      expect(blocked.isBlockedByViewer, isTrue);
      expect(legacy.isBlockedByViewer, isFalse);
    });

    test('blocked user list is parsed from the items envelope', () async {
      final client = FakeApiClient();
      client.setHandler(
          'GET',
          'users/me/blocks',
          (_) => {
                'items': [
                  {
                    'id': 'b1',
                    'name': 'Bob',
                    'avatar_url': null,
                    'blocked_at': '2026-10-01T10:00:00Z',
                  }
                ],
                'limit': 200,
              });
      final users = await MushukistanApi(client: client).listBlockedUsers();
      expect(users, hasLength(1));
      expect(users.single.id, 'b1');
      expect(users.single.name, 'Bob');
      expect(client.calls.single.authenticated, isTrue);
    });
  });

  group('public reads carry the viewer token so the server can apply blocks',
      () {
    test('lists, map and comments are sent with authentication', () async {
      final client = FakeApiClient();
      Object? page(Object? _) => {'items': <Object?>[], 'limit': 20};
      for (final path in [
        'cats',
        'lost-pets',
        'lost-pets/map',
        'adoption-posts',
        'posts/p1/comments',
        'lost-pets/l1/comments',
        'adoption-posts/a1/comments',
      ]) {
        client.setHandler('GET', path, page);
      }
      client.setHandler(
          'GET',
          'users/u1',
          (_) => {
                'id': 'u1',
                'registered_at': '2026-07-01T10:00:00Z',
              });
      final api = MushukistanApi(client: client);
      await api.listCats(filter: 'recently_added', bbox: '1,2,3,4');
      await api.listLostPets();
      await api.listMapLostPets(bbox: '1,2,3,4');
      await api.listAdoptionPosts();
      await api.listComments('p1');
      await api.listLostPetComments('l1');
      await api.listAdoptionPostComments('a1');
      await api.getPublicProfile('u1');
      expect(client.calls, hasLength(8));
      expect(client.calls.every((call) => call.authenticated), isTrue,
          reason: 'anonymous users simply have no token to send');
    });
  });

  group('BlockedUsersScreen', () {
    Future<(FakeApiClient, ProviderContainer)> mount(
      WidgetTester tester,
      List<Map<String, Object?>> users,
    ) async {
      final client = FakeApiClient();
      var current = [...users];
      client.setHandler(
          'GET', 'users/me/blocks', (_) => {'items': current, 'limit': 200});
      client.setHandler('DELETE', 'users/b1/block', (_) {
        current = current.where((user) => user['id'] != 'b1').toList();
        return null;
      });
      final container = ProviderContainer(overrides: [
        apiClientProvider.overrideWithValue(client),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: BlockedUsersScreen()),
      ));
      await tester.pumpAndSettle();
      return (client, container);
    }

    testWidgets('empty state', (tester) async {
      await mount(tester, []);
      expect(find.text('You have not blocked anyone.'), findsOneWidget);
    });

    testWidgets('unblocking removes the row and refreshes dependent data',
        (tester) async {
      final (client, container) = await mount(tester, [
        {
          'id': 'b1',
          'name': 'Bob',
          'avatar_url': null,
          'blocked_at': '2026-10-01T10:00:00Z',
        },
        {
          'id': 'b2',
          'name': 'Carol',
          'avatar_url': null,
          'blocked_at': '2026-09-01T10:00:00Z',
        },
      ]);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Carol'), findsOneWidget);
      final before = container.read(postMutationRevisionProvider);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Unblock').first);
      await tester.pumpAndSettle();
      expect(client.calls.where((c) => c.method == 'DELETE'), hasLength(1));
      expect(find.text('Bob'), findsNothing);
      expect(find.text('Carol'), findsOneWidget);
      expect(container.read(postMutationRevisionProvider), greaterThan(before));
    });

    testWidgets('a failed unblock keeps the row and shows an error',
        (tester) async {
      final (client, _) = await mount(tester, [
        {
          'id': 'b1',
          'name': 'Bob',
          'avatar_url': null,
          'blocked_at': '2026-10-01T10:00:00Z',
        },
      ]);
      client.setHandler('DELETE', 'users/b1/block', (_) {
        throw StateError('offline');
      });
      await tester.tap(find.widgetWithText(OutlinedButton, 'Unblock'));
      await tester.pumpAndSettle();
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Could not update the block. Please try again.'),
          findsOneWidget);
    });
  });
}
