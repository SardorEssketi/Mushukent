import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mushukistan_frontend/core/network/api_error.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';
import 'package:mushukistan_frontend/features/auth/application/auth_controller.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_models.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_repository.dart';
import 'package:mushukistan_frontend/features/auth/presentation/screens/auth_required_screen.dart';
import 'package:mushukistan_frontend/features/comments/presentation/screens/comments_screen.dart';

import '../../support/fakes.dart';

void main() {
  group('comment mutation feedback', () {
    testWidgets('guest comment action requests authentication', (tester) async {
      final client = _client();
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const Scaffold(
              body: PostCommentsSection(postId: 'post-1'),
            ),
          ),
          GoRoute(
            path: '/auth-required',
            builder: (context, state) => AuthRequiredScreen(
              redirect: state.uri.queryParameters['redirect'],
            ),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mushukistanApiProvider.overrideWithValue(
              MushukistanApi(client: client),
            ),
            commentsProvider('post-1').overrideWith(
              (ref) async => const ApiPage<CommentData>(items: [], limit: 20),
            ),
            authRepositoryProvider.overrideWithValue(
              FakeAuthRepository(
                restoreResult: const SessionRestoreMissing(),
              ),
            ),
            googleIdentityTokenProvider.overrideWithValue(
              FakeGoogleIdentityTokenProvider(),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      expect(find.text('Account required'), findsOneWidget);
      expect(client.calls, isEmpty);
    });

    testWidgets('successful create shows one posted message', (tester) async {
      final client = _client();
      client.setHandler('POST', 'posts/post-1/comments', (_) {
        return _commentPayload(content: 'New comment');
      });

      await _pumpComments(tester, client: client);
      await tester.enterText(find.byType(TextField), 'New comment');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Comment posted'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Another comment');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Comment posted'), findsOneWidget);
    });

    testWidgets('failed create does not show posted message', (tester) async {
      final client = _client();
      client.setHandler('POST', 'posts/post-1/comments', (_) {
        throw const MushukistanApiException(
          kind: ApiFailureKind.server,
          code: 'REQUEST_FAILED',
          message: 'Could not post comment.',
        );
      });

      await _pumpComments(tester, client: client);
      await tester.enterText(find.byType(TextField), 'New comment');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Comment posted'), findsNothing);
    });

    testWidgets('successful edit shows updated message', (tester) async {
      final client = _client();
      client.setHandler('PATCH', 'comments/comment-1', (_) {
        return _commentPayload(
          content: 'Edited comment',
          editedAt: '2026-09-20T10:05:00Z',
        );
      });

      await _pumpComments(tester, client: client, comment: _comment());
      await _openEdit(tester, 'Edited comment');

      expect(find.text('Comment updated'), findsOneWidget);
    });

    testWidgets('failed edit does not show updated message', (tester) async {
      final client = _client();
      client.setHandler('PATCH', 'comments/comment-1', (_) {
        throw const MushukistanApiException(
          kind: ApiFailureKind.forbidden,
          code: 'COMMENT_EDIT_WINDOW_EXPIRED',
          message: 'The comment editing window has expired.',
        );
      });

      await _pumpComments(tester, client: client, comment: _comment());
      await _openEdit(tester, 'Edited comment');

      expect(find.text('Comment updated'), findsNothing);
    });

    testWidgets('successful delete shows deleted message', (tester) async {
      final client = _client();
      client.setHandler('DELETE', 'comments/comment-1', (_) => null);

      await _pumpComments(tester, client: client, comment: _comment());
      await _deleteComment(tester);

      expect(find.text('Comment deleted'), findsOneWidget);
    });

    testWidgets('failed delete does not show deleted message', (tester) async {
      final client = _client();
      client.setHandler('DELETE', 'comments/comment-1', (_) {
        throw const MushukistanApiException(
          kind: ApiFailureKind.forbidden,
          code: 'FORBIDDEN',
          message: 'You do not have permission to perform this action.',
        );
      });

      await _pumpComments(tester, client: client, comment: _comment());
      await _deleteComment(tester);

      expect(find.text('Comment deleted'), findsNothing);
    });
  });
}

Future<void> _pumpComments(
  WidgetTester tester, {
  required FakeApiClient client,
  CommentData? comment,
}) async {
  final items =
      comment == null ? const <CommentData>[] : <CommentData>[comment];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        mushukistanApiProvider.overrideWithValue(
          MushukistanApi(client: client),
        ),
        commentsProvider('post-1').overrideWith(
          (ref) async => ApiPage<CommentData>(items: items, limit: 20),
        ),
        currentUserProvider.overrideWithValue(_user()),
        authControllerProvider.overrideWith(
          (ref) => AuthController(
            FakeAuthRepository(
              restoreResult: SessionRestoreSuccess(
                AuthSession.restored(
                  accessToken: 'test-token',
                  user: _user(),
                ),
              ),
            ),
            FakeGoogleIdentityTokenProvider(),
          ),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: PostCommentsSection(
            postId: 'post-1',
            now: DateTime.utc(2026, 9, 20, 10, 5),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

FakeApiClient _client() {
  final client = FakeApiClient();
  return client;
}

MushukistanUser _user() {
  return MushukistanUser(
    id: 'user-1',
    name: 'Author',
    registeredAt: DateTime.utc(2026, 1, 1),
  );
}

CommentData _comment() {
  return CommentData(
    id: 'comment-1',
    postId: 'post-1',
    user: const CommentUserData(id: 'user-1', name: 'Author'),
    content: 'Original comment',
    createdAt: DateTime.utc(2026, 9, 20, 10),
    editUntil: DateTime.utc(2026, 9, 20, 10, 30),
  );
}

Future<void> _openEdit(WidgetTester tester, String replacement) async {
  await tester.tap(find.byIcon(Icons.more_vert));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Edit comment'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).last, replacement);
  await tester.tap(find.text('Save changes'));
  await tester.pumpAndSettle();
}

Future<void> _deleteComment(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.more_vert));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Delete comment'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Delete'));
  await tester.pumpAndSettle();
}

Map<String, Object?> _commentPayload({
  required String content,
  String? editedAt,
}) {
  return {
    'id': 'comment-1',
    'post_id': 'post-1',
    'lost_pet_id': null,
    'adoption_post_id': null,
    'parent_comment_id': null,
    'user': {'id': 'user-1', 'name': 'Author'},
    'content': content,
    'created_at': '2026-09-20T10:00:00Z',
    'edited_at': editedAt,
    'edit_until': '2026-09-20T10:30:00Z',
  };
}
