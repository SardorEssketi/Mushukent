import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';
import 'package:mushukistan_frontend/features/comments/presentation/screens/comments_screen.dart';
import 'package:mushukistan_frontend/features/moderation/presentation/screens/post_history_screen.dart';

import '../../support/fakes.dart';

void main() {
  group('post mutations', () {
    test('updates mutable fields through the owner post endpoint', () async {
      final client = FakeApiClient();
      final api = MushukistanApi(client: client);
      client.setHandler('PATCH', 'posts/post-1', (call) {
        expect(call.authenticated, isTrue);
        expect(call.body, <String, Object?>{
          'description': 'Updated description',
          'location': null,
          'is_public': false,
          'status': 'healthy',
        });
        return _postPayload(
          description: 'Updated description',
          isPublic: false,
          isEdited: true,
        );
      });

      final post = await api.updateObservation(
        postId: 'post-1',
        description: ' Updated description ',
        location: null,
        isPublic: false,
        status: 'healthy',
      );

      expect(post.description, 'Updated description');
      expect(post.isPublic, isFalse);
      expect(post.isEdited, isTrue);
      expect(client.calls.single.method, 'PATCH');
    });

    test('parses moderator post history snapshots', () async {
      final client = FakeApiClient();
      final api = MushukistanApi(client: client);
      client.setHandler('GET', 'moderation/posts/post-1/history', (_) {
        return [
          {
            'id': 'history-1',
            'post_id': 'post-1',
            'actor_id': 'user-1',
            'actor_name': 'Editor',
            'action': 'edited',
            'before': {
              'description': 'Before',
              'photo_urls': ['old.jpg']
            },
            'after': {
              'description': 'After',
              'photo_urls': ['new.jpg']
            },
            'created_at': '2026-09-19T10:00:00Z',
          },
        ];
      });

      final history = await api.getPostHistory('post-1');

      expect(history, hasLength(1));
      expect(history.single.before['description'], 'Before');
      expect(history.single.after['photo_urls'], ['new.jpg']);
    });

    test('compares nested history values by content', () {
      expect(
        historyValuesEqual(
          {
            'latitude': 41.3,
            'metadata': ['one', 'two'],
          },
          {
            'latitude': 41.3,
            'metadata': ['one', 'two'],
          },
        ),
        isTrue,
      );
      expect(
        historyValuesEqual(['old.jpg'], ['new.jpg']),
        isFalse,
      );
    });

    test('updates and deletes comments with edit metadata', () async {
      final client = FakeApiClient();
      final api = MushukistanApi(client: client);
      client.setHandler('PATCH', 'comments/comment-1', (call) {
        expect(call.authenticated, isTrue);
        expect(call.body, <String, Object?>{'content': 'Edited comment'});
        return _commentPayload(
          content: 'Edited comment',
          editedAt: '2026-09-19T10:05:00Z',
          editUntil: '2026-09-19T10:30:00Z',
        );
      });
      client.setHandler('DELETE', 'comments/comment-1', (call) {
        expect(call.authenticated, isTrue);
        return null;
      });

      final updated = await api.updateComment('comment-1', 'Edited comment');
      await api.deleteComment('comment-1');

      expect(updated.content, 'Edited comment');
      expect(updated.editedAt, DateTime.parse('2026-09-19T10:05:00Z'));
      expect(updated.editUntil, DateTime.parse('2026-09-19T10:30:00Z'));
      expect(client.calls.map((call) => call.method), ['PATCH', 'DELETE']);
    });

    test('uses the server edit deadline at the exact boundary', () {
      final comment = CommentData.fromJson(
        _commentPayload(
          content: 'Comment',
          editUntil: '2026-09-19T10:30:00Z',
        ),
      );

      expect(
        isCommentEditable(comment, now: DateTime.parse('2026-09-19T10:29:59Z')),
        isTrue,
      );
      expect(
        isCommentEditable(comment, now: DateTime.parse('2026-09-19T10:30:00Z')),
        isFalse,
      );
    });
  });
}

Map<String, Object?> _postPayload({
  required String description,
  required bool isPublic,
  bool isEdited = false,
}) {
  return {
    'id': 'post-1',
    'cat': {'id': 'cat-1', 'status': 'unknown'},
    'author': {'id': 'user-1', 'name': 'Author'},
    'photo_url': 'https://example.com/post.jpg',
    'photo_urls': ['https://example.com/post.jpg'],
    'description': description,
    'location': null,
    'created_at': '2026-09-19T09:00:00Z',
    'updated_at': '2026-09-19T10:00:00Z',
    'is_public': isPublic,
    'is_edited': isEdited,
    'like_count': 0,
    'comment_count': 0,
    'is_liked_by_me': false,
  };
}

Map<String, Object?> _commentPayload({
  required String content,
  String? editedAt,
  String? editUntil,
}) {
  return {
    'id': 'comment-1',
    'post_id': 'post-1',
    'parent_comment_id': null,
    'user': {'id': 'user-1', 'name': 'Author'},
    'content': content,
    'created_at': '2026-09-19T10:00:00Z',
    'edited_at': editedAt,
    'edit_until': editUntil,
  };
}
