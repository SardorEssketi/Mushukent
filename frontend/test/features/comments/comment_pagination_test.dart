import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/core/network/api_error.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';
import 'package:mushukistan_frontend/features/auth/application/auth_controller.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_models.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_repository.dart';
import 'package:mushukistan_frontend/features/comments/application/comment_thread_controller.dart';
import 'package:mushukistan_frontend/features/comments/presentation/screens/comments_screen.dart';

import '../../support/fakes.dart';

/// Server-side thread: keyset pages over undeleted, unblocked comments in
/// ascending creation order, like `GET .../comments?order=asc`.
class _FakeThread {
  _FakeThread(int count) {
    for (var i = 1; i <= count; i++) {
      add('P-$i');
    }
  }

  final rows = <Map<String, Object?>>[];
  final hidden = <String>{};
  int _clock = 0;
  bool failNextContinuation = false;
  int pageRequests = 0;

  Map<String, Object?> add(String content, {String? parentId}) {
    _clock++;
    final row = <String, Object?>{
      'id': 'c-${_clock.toString().padLeft(4, '0')}',
      'post_id': 'post-1',
      'lost_pet_id': null,
      'adoption_post_id': null,
      'parent_comment_id': parentId,
      'user': {'id': 'user-1', 'name': 'Author'},
      'content': content,
      'created_at': DateTime.utc(2026, 11, 5, 10)
          .add(Duration(seconds: _clock))
          .toIso8601String(),
      'edit_until': '2026-11-05T10:30:00Z',
    };
    rows.add(row);
    return row;
  }

  Object? page(ApiCall call) {
    pageRequests++;
    final query = call.queryParameters ?? const <String, dynamic>{};
    expect(query['order'], 'asc');
    final cursor = query['cursor'] as String?;
    if (cursor != null && failNextContinuation) {
      failNextContinuation = false;
      throw const MushukistanApiException(
        kind: ApiFailureKind.server,
        code: 'REQUEST_FAILED',
        message: 'Temporary failure',
      );
    }
    final visible = rows.where((row) => !hidden.contains(row['id'])).toList();
    final start = cursor == null
        ? 0
        : visible
            .indexWhere((row) => (row['id'] as String).compareTo(cursor) > 0);
    final from = start < 0 ? visible.length : start;
    final limit = query['limit'] as int;
    expect(limit, 20);
    final items = visible.skip(from).take(limit).toList();
    final more = from + items.length < visible.length;
    return {
      'items': items,
      'limit': limit,
      'next_cursor': more ? items.last['id'] : null,
    };
  }
}

MushukistanUser _user() => MushukistanUser(
      id: 'user-1',
      name: 'Author',
      registeredAt: DateTime.utc(2026, 1, 1),
    );

Future<FakeApiClient> _pump(
  WidgetTester tester,
  _FakeThread thread, {
  String path = 'posts/post-1/comments',
  Widget? section,
}) async {
  tester.view.physicalSize = const Size(800, 12000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final client = FakeApiClient()..setHandler('GET', path, thread.page);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        mushukistanApiProvider
            .overrideWithValue(MushukistanApi(client: client)),
        currentUserProvider.overrideWithValue(_user()),
        authControllerProvider.overrideWith(
          (ref) => AuthController(
            FakeAuthRepository(
              restoreResult: SessionRestoreSuccess(
                AuthSession.restored(accessToken: 'token', user: _user()),
              ),
            ),
            FakeGoogleIdentityTokenProvider(),
          )..restoreSession(),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: section ??
                PostCommentsSection(
                  postId: 'post-1',
                  now: DateTime.utc(2026, 11, 5, 10, 5),
                ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return client;
}

final _showMore = find.text('Show more comments');

Future<void> _tapShowMore(WidgetTester tester) async {
  await tester.ensureVisible(_showMore);
  await tester.tap(_showMore);
  await tester.pumpAndSettle();
}

Future<void> _loadAll(WidgetTester tester) async {
  for (var i = 0; i < 10 && _showMore.evaluate().isNotEmpty; i++) {
    await _tapShowMore(tester);
  }
}

Future<void> _openMenuFor(WidgetTester tester, String content) async {
  await tester.ensureVisible(find.text(content));
  await tester.pumpAndSettle();
  final y = tester.getCenter(find.text(content)).dy;
  final menus = find.byIcon(Icons.more_vert);
  var closest = menus.first;
  var best = double.infinity;
  for (var i = 0; i < menus.evaluate().length; i++) {
    final distance = (tester.getCenter(menus.at(i)).dy - y).abs();
    if (distance < best) {
      best = distance;
      closest = menus.at(i);
    }
  }
  await tester.tap(closest);
  await tester.pumpAndSettle();
}

void _expectExactlyOnce(Iterable<String> contents) {
  for (final content in contents) {
    expect(find.text(content), findsOneWidget, reason: content);
  }
}

List<String> _contents(int from, int to) =>
    [for (var i = from; i <= to; i++) 'P-$i'];

void main() {
  for (final count in [0, 1, 20]) {
    testWidgets('$count comments: single page, no continuation',
        (tester) async {
      final thread = _FakeThread(count);
      await _pump(tester, thread);

      _expectExactlyOnce(_contents(1, count));
      expect(_showMore, findsNothing);
      expect(find.text('No comments yet.'),
          count == 0 ? findsOneWidget : findsNothing);
      expect(thread.pageRequests, 1);
    });
  }

  testWidgets('21 comments: the 21st is reachable with Show more',
      (tester) async {
    final thread = _FakeThread(21);
    await _pump(tester, thread);

    _expectExactlyOnce(_contents(1, 20));
    expect(find.text('P-21'), findsNothing);
    await _tapShowMore(tester);

    _expectExactlyOnce(_contents(1, 21));
    expect(_showMore, findsNothing);
    expect(thread.pageRequests, 2);
  });

  testWidgets('45 comments load in three ordered pages without duplicates',
      (tester) async {
    final thread = _FakeThread(45);
    final client = await _pump(tester, thread);

    await _tapShowMore(tester);
    _expectExactlyOnce(_contents(1, 40));
    await _tapShowMore(tester);
    _expectExactlyOnce(_contents(1, 45));
    expect(_showMore, findsNothing);

    final cursors = client.calls
        .map((call) => call.queryParameters?['cursor'])
        .toList(growable: false);
    expect(cursors, [null, 'c-0020', 'c-0040']);
    final shown = tester
        .widgetList<Text>(find.textContaining(RegExp(r'^P-\d+$')))
        .map((text) => text.data)
        .toList();
    expect(shown, _contents(1, 45));
  });

  testWidgets('replies on a later page nest under their earlier parent',
      (tester) async {
    final thread = _FakeThread(20);
    final parent = thread.rows[2];
    thread.add('Reply to P-3', parentId: parent['id'] as String);
    await _pump(tester, thread);

    expect(find.text('Reply to P-3'), findsNothing);
    await _tapShowMore(tester);

    expect(find.text('Reply to P-3'), findsOneWidget);
    final parentTop = tester.getTopLeft(find.text('P-3')).dy;
    final replyTop = tester.getTopLeft(find.text('Reply to P-3')).dy;
    final nextRootTop = tester.getTopLeft(find.text('P-4')).dy;
    expect(replyTop, greaterThan(parentTop));
    expect(replyTop, lessThan(nextRootTop));
  });

  testWidgets(
      'comments added while paginating appear once and a new own comment '
      'is shown in place after the remaining pages', (tester) async {
    final thread = _FakeThread(25);
    final client = await _pump(tester, thread);
    // Someone else comments after page 1 was loaded.
    thread.add('Late other comment');

    client.setHandler(
        'POST', 'posts/post-1/comments', (_) => thread.add('My new comment'));
    await tester.enterText(find.byType(TextField), 'My new comment');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Comment posted'), findsOneWidget);
    _expectExactlyOnce(
        [..._contents(1, 25), 'Late other comment', 'My new comment']);
    expect(_showMore, findsNothing);
    final lateTop = tester.getTopLeft(find.text('Late other comment')).dy;
    final mineTop = tester.getTopLeft(find.text('My new comment')).dy;
    expect(tester.getTopLeft(find.text('P-25')).dy, lessThan(lateTop));
    expect(lateTop, lessThan(mineTop));
    // No first-page reload: page 1 once, then continuation only.
    expect(
      client.calls
          .where((call) =>
              call.method == 'GET' && call.queryParameters?['cursor'] == null)
          .length,
      1,
    );
  });

  testWidgets('a new comment at the end of a fully loaded thread is shown',
      (tester) async {
    final thread = _FakeThread(3);
    final client = await _pump(tester, thread);
    client.setHandler(
        'POST', 'posts/post-1/comments', (_) => thread.add('Fresh'));

    await tester.enterText(find.byType(TextField), 'Fresh');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();

    _expectExactlyOnce([..._contents(1, 3), 'Fresh']);
    expect(thread.pageRequests, 1);
  });

  testWidgets('deleted and blocked comments stay hidden across pages',
      (tester) async {
    final thread = _FakeThread(30);
    // The API omits deleted comments and comments of blocked users.
    thread.hidden.addAll({'c-0005', 'c-0024'});
    await _pump(tester, thread);
    await _loadAll(tester);

    expect(find.text('P-5'), findsNothing);
    expect(find.text('P-24'), findsNothing);
    _expectExactlyOnce([
      for (final c in _contents(1, 30))
        if (c != 'P-5' && c != 'P-24') c,
    ]);
  });

  testWidgets('edit and delete on a later page keep loaded pages and identity',
      (tester) async {
    final thread = _FakeThread(22);
    final client = await _pump(tester, thread);
    await _tapShowMore(tester);
    final target = thread.rows[21];
    client.setHandler('PATCH', 'comments/${target['id']}', (_) {
      target['content'] = 'P-22 edited';
      target['edited_at'] = '2026-11-05T10:04:00Z';
      return target;
    });
    client.setHandler('DELETE', 'comments/c-0021', (_) => null);

    await _openMenuFor(tester, 'P-22');
    await tester.tap(find.text('Edit comment'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'P-22 edited');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(find.text('P-22 edited'), findsOneWidget);
    expect(find.text('P-22'), findsNothing);
    _expectExactlyOnce(_contents(1, 21));

    await _openMenuFor(tester, 'P-21');
    await tester.tap(find.text('Delete comment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('P-21'), findsNothing);
    _expectExactlyOnce([..._contents(1, 20), 'P-22 edited']);
    // Mutations are applied locally: no thread reload after them.
    expect(thread.pageRequests, 2);
  });

  testWidgets('a failed continuation keeps loaded comments and can retry',
      (tester) async {
    final thread = _FakeThread(23)..failNextContinuation = true;
    await _pump(tester, thread);

    await _tapShowMore(tester);
    expect(find.text('Could not load more comments.'), findsOneWidget);
    _expectExactlyOnce(_contents(1, 20));
    expect(find.text('P-21'), findsNothing);

    await tester.ensureVisible(find.text('Retry'));
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Could not load more comments.'), findsNothing);
    _expectExactlyOnce(_contents(1, 23));
    expect(_showMore, findsNothing);
  });

  testWidgets('Lost Pet discussions paginate through the shared renderer',
      (tester) async {
    final thread = _FakeThread(21);
    await _pump(
      tester,
      thread,
      path: 'lost-pets/lost-1/comments',
      section: const LostPetCommentsSection(lostPetId: 'lost-1'),
    );
    await _tapShowMore(tester);
    _expectExactlyOnce(_contents(1, 21));
  });

  testWidgets('Adoption discussions paginate through the shared renderer',
      (tester) async {
    final thread = _FakeThread(21);
    await _pump(
      tester,
      thread,
      path: 'adoption-posts/adoption-1/comments',
      section: const AdoptionPostCommentsSection(adoptionPostId: 'adoption-1'),
    );
    await _tapShowMore(tester);
    _expectExactlyOnce(_contents(1, 21));
  });

  testWidgets('a refresh during a continuation discards the stale page',
      (tester) async {
    final thread = _FakeThread(25);
    final client = await _pump(tester, thread);
    final gate = Completer<void>();
    client.setHandler('GET', 'posts/post-1/comments', (call) async {
      if (call.queryParameters?['cursor'] != null && !gate.isCompleted) {
        await gate.future;
      }
      return thread.page(call);
    });

    await tester.ensureVisible(_showMore);
    await tester.tap(_showMore);
    await tester.pump();
    final container = ProviderScope.containerOf(
        tester.element(find.byType(PostCommentsSection)));
    container.invalidate(commentsProvider('post-1'));
    await tester.pumpAndSettle();
    gate.complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    _expectExactlyOnce(_contents(1, 20));
    expect(find.text('P-21'), findsNothing);
    expect(_showMore, findsOneWidget);
    await _tapShowMore(tester);
    _expectExactlyOnce(_contents(1, 25));
  });

  testWidgets('leaving while a continuation loads does not throw',
      (tester) async {
    final thread = _FakeThread(25);
    final client = await _pump(tester, thread);
    final gate = Completer<void>();
    client.setHandler('GET', 'posts/post-1/comments', (call) async {
      if (call.queryParameters?['cursor'] != null) await gate.future;
      return thread.page(call);
    });
    client.setHandler(
        'POST', 'posts/post-1/comments', (_) => thread.add('Posted'));

    await tester.enterText(find.byType(TextField), 'Posted');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    gate.complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  group('mergeComments', () {
    CommentData comment(String id, int second, String content) =>
        CommentData.fromJson({
          'id': id,
          'post_id': 'post-1',
          'content': content,
          'created_at':
              DateTime.utc(2026, 11, 5, 10, 0, second).toIso8601String(),
        });

    test('dedupes overlapping pages by id and keeps API order', () {
      final merged = mergeComments(
        [comment('b', 2, 'B'), comment('a', 1, 'A')],
        [comment('b', 2, 'B updated'), comment('c', 2, 'C')],
      );
      expect(merged.map((c) => c.id), ['a', 'b', 'c']);
      expect(merged[1].content, 'B updated');
    });
  });
}
