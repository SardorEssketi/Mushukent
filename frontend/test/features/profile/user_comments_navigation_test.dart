import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mushukistan_frontend/core/network/api_client.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';
import 'package:mushukistan_frontend/features/auth/application/auth_controller.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_models.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_repository.dart';
import 'package:mushukistan_frontend/features/profile/presentation/screens/user_activity_screen.dart';

import '../../support/fakes.dart';

Map<String, Object?> _comment(
  String id,
  String content, {
  String? postId,
  String? lostPetId,
  String? adoptionPostId,
}) =>
    {
      'id': id,
      'post_id': postId,
      'lost_pet_id': lostPetId,
      'adoption_post_id': adoptionPostId,
      'parent_comment_id': null,
      'user': {'id': 'bob', 'name': 'Bob'},
      'content': content,
      'created_at': '2026-11-05T11:00:00Z',
    };

void main() {
  group('commentActivityRoute', () {
    CommentData data(Map<String, Object?> json) => CommentData.fromJson(json);

    test('routes each target kind by its own non-null identifier', () {
      expect(commentActivityRoute(data(_comment('c1', 'x', postId: 'p1'))),
          '/posts/p1');
      expect(commentActivityRoute(data(_comment('c2', 'x', lostPetId: 'l1'))),
          '/lost-pets/l1');
      expect(
          commentActivityRoute(data(_comment('c3', 'x', adoptionPostId: 'a1'))),
          '/adoption-posts/a1');
    });

    test('never builds a route from a missing identifier', () {
      expect(commentActivityRoute(data(_comment('c4', 'x'))), isNull);
      expect(
          commentActivityRoute(data(_comment('c5', 'x', postId: ' '))), isNull);
    });
  });

  testWidgets(
      'My comments opens ordinary, Needs Help, Lost Pet and Adoption targets',
      (tester) async {
    final client = FakeApiClient();
    client.setHandler(
        'GET',
        'users/bob/comments',
        (_) => {
              'items': [
                _comment('c-ordinary', 'Ordinary comment',
                    postId: 'post-ordinary'),
                _comment('c-help', 'Needs Help comment', postId: 'post-help'),
                _comment('c-lost', 'I may have seen Luna',
                    lostPetId: '0ad80f75-8427-482e-82dd-428283964445'),
                _comment('c-adoption', 'Is Kesha still available?',
                    adoptionPostId: '066b7b34-0edd-4b0e-8fa4-42df425d73cf'),
                _comment('c-orphan', 'Target unknown'),
              ],
              'limit': 50,
            });
    final container = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(client),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(
        restoreResult: SessionRestoreSuccess(
            AuthSession.restored(accessToken: 'token', user: testUser())),
      )),
      googleIdentityTokenProvider
          .overrideWithValue(FakeGoogleIdentityTokenProvider()),
    ]);
    addTearDown(container.dispose);
    await container.read(authControllerProvider.notifier).restoreSession();

    Widget destination(String label, GoRouterState state) => Scaffold(
          appBar: AppBar(),
          body: Text('$label ${state.pathParameters.values.single}'),
        );
    final router = GoRouter(initialLocation: '/comments', routes: [
      GoRoute(
        path: '/comments',
        builder: (_, __) =>
            const UserCommentsScreen(userId: 'bob', isCurrentUser: true),
      ),
      GoRoute(
          path: '/posts/:postId',
          builder: (_, state) => destination('Post', state)),
      GoRoute(
          path: '/lost-pets/:lostPetId',
          builder: (_, state) => destination('Lost', state)),
      GoRoute(
          path: '/adoption-posts/:adoptionPostId',
          builder: (_, state) => destination('Adoption', state)),
    ]);
    addTearDown(router.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();

    Future<void> openAndReturn(String tile, String expected) async {
      await tester.tap(find.text(tile));
      await tester.pumpAndSettle();
      expect(find.text(expected), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text(tile), findsOneWidget);
    }

    await openAndReturn('Ordinary comment', 'Post post-ordinary');
    await openAndReturn('Needs Help comment', 'Post post-help');
    await openAndReturn(
        'I may have seen Luna', 'Lost 0ad80f75-8427-482e-82dd-428283964445');
    await openAndReturn('Is Kesha still available?',
        'Adoption 066b7b34-0edd-4b0e-8fa4-42df425d73cf');

    await tester.tap(find.text('Target unknown'));
    await tester.pumpAndSettle();
    expect(find.text('Target unknown'), findsOneWidget);
    expect(router.routerDelegate.currentConfiguration.uri.path, '/comments');

    final requested = client.calls.map((call) => call.path).toList();
    expect(requested.where((path) => path.contains('null')), isEmpty);
    expect(tester.takeException(), isNull);
  });
}
