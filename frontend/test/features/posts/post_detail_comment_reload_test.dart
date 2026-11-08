// NEW-02: posting or deleting a comment on a long ordinary-post discussion must
// keep the loaded comment pages and the scroll position. The mutation reloads the
// post detail; that reload must not replace the page with a loading state (which
// disposed the paginated thread and reset it to page 1).
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

const _postId = '22222222-2222-4222-8222-222222222222';

class _Thread {
  _Thread(int count) {
    for (var i = 1; i <= count; i++) {
      add('C-$i');
    }
  }

  final rows = <Map<String, Object?>>[];
  final deleted = <String>{};
  int _clock = 0;

  Map<String, Object?> add(String content) {
    _clock++;
    final row = <String, Object?>{
      'id': 'c-${_clock.toString().padLeft(4, '0')}',
      'post_id': _postId,
      'parent_comment_id': null,
      'user': {'id': 'owner-1', 'name': 'Owner'},
      'content': content,
      'created_at': DateTime.utc(2026, 11, 5, 10)
          .add(Duration(seconds: _clock))
          .toIso8601String(),
      'edit_until': '2030-01-01T00:00:00Z',
    };
    rows.add(row);
    return row;
  }

  Object? page(ApiCall call) {
    final query = call.queryParameters ?? const <String, dynamic>{};
    final cursor = query['cursor'] as String?;
    final visible = rows.where((r) => !deleted.contains(r['id'])).toList();
    final start = cursor == null
        ? 0
        : visible.indexWhere((r) => (r['id'] as String).compareTo(cursor) > 0);
    final from = start < 0 ? visible.length : start;
    final limit = query['limit'] as int;
    final items = visible.skip(from).take(limit).toList();
    return {
      'items': items,
      'limit': limit,
      'next_cursor':
          from + items.length < visible.length ? items.last['id'] : null,
    };
  }

  Map<String, Object?> post() => {
        'id': _postId,
        'cat': {'id': 'cat-1', 'status': 'unknown', 'name': 'Synthetic cat'},
        'author': {'id': 'owner-1', 'name': 'Owner'},
        'photo_url': 'https://example.com/cat.jpg',
        'photo_urls': ['https://example.com/cat.jpg'],
        'location': null,
        'description': 'Synthetic post',
        'kind': 'observation',
        'created_at': '2026-10-01T00:00:00Z',
        'like_count': 0,
        'comment_count': rows.length - deleted.length,
        'is_liked_by_me': false,
      };
}

Future<FakeApiClient> _mount(WidgetTester tester, _Thread thread) async {
  tester.view.physicalSize = const Size(390, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final client = FakeApiClient()
    // Asynchronous like a real request, so a reload has a loading phase.
    ..setHandler(
        'GET',
        'posts/$_postId',
        (_) => Future<Object?>.delayed(
            const Duration(milliseconds: 50), thread.post))
    ..setHandler('GET', 'posts/$_postId/comments', thread.page)
    ..setHandler('POST', 'posts/$_postId/views', (_) => null);
  final router = GoRouter(initialLocation: '/posts/$_postId', routes: [
    GoRoute(
        path: '/feed', builder: (_, __) => const Scaffold(body: Text('Feed'))),
    GoRoute(
      path: '/posts/:id',
      builder: (_, state) =>
          PostDetailScreen(postId: state.pathParameters['id']!),
    ),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      mushukistanApiProvider.overrideWithValue(MushukistanApi(client: client)),
      currentUserProvider.overrideWithValue(testUser(id: 'owner-1')),
      authControllerProvider.overrideWith(
        (ref) => AuthController(
          FakeAuthRepository(
            restoreResult: SessionRestoreSuccess(AuthSession.restored(
                accessToken: 'token', user: testUser(id: 'owner-1'))),
          ),
          FakeGoogleIdentityTokenProvider(),
        )..restoreSession(),
      ),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return client;
}

final _showMore = find.text('Show more comments');

int _firstPageRequests(FakeApiClient client) => client.calls
    .where((c) =>
        c.method == 'GET' &&
        c.path == 'posts/$_postId/comments' &&
        c.queryParameters?['cursor'] == null)
    .length;

ScrollPosition _scroll(WidgetTester tester) =>
    tester.state<ScrollableState>(find.byType(Scrollable).first).position;

Future<void> _loadPageTwo(WidgetTester tester) async {
  await tester.scrollUntilVisible(_showMore, 300,
      scrollable: find.byType(Scrollable).first);
  await tester.tap(_showMore);
  await tester.pumpAndSettle();
  expect(_showMore, findsNothing);
}

void main() {
  testWidgets(
      'posting on page 2 keeps loaded pages, scroll and shows the comment',
      (tester) async {
    final thread = _Thread(25);
    final client = await _mount(tester, thread);
    await _loadPageTwo(tester);
    expect(_firstPageRequests(client), 1);

    client.setHandler(
        'POST', 'posts/$_postId/comments', (_) => thread.add('Brand new'));
    await tester.scrollUntilVisible(find.byType(TextField), -300,
        scrollable: find.byType(Scrollable).first);
    final before = _scroll(tester).pixels;
    expect(before, greaterThan(0));
    await tester.enterText(find.byType(TextField).last, 'Brand new');
    await tester.ensureVisible(find.byTooltip('Post comment'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Post comment'));
    await tester.pumpAndSettle();

    expect(
        client.calls
            .where((c) =>
                c.method == 'POST' && c.path == 'posts/$_postId/comments')
            .length,
        1);
    // The composer was cleared, so 'Brand new' below is the rendered comment.
    expect(
        (tester.widget<TextField>(find.byType(TextField).last))
                .controller
                ?.text ??
            '',
        isEmpty);

    // The detail reloaded (mutation revision) ...
    expect(
        client.calls
            .where((c) => c.method == 'GET' && c.path == 'posts/$_postId')
            .length,
        greaterThan(1));
    // ... but the thread kept its pages: no first-page refetch, no Show more,
    // page-2 comments and the new comment are all present exactly once.
    expect(_firstPageRequests(client), 1);
    expect(_showMore, findsNothing);
    for (final text in ['C-1', 'C-21', 'C-25', 'Brand new']) {
      expect(find.text(text, skipOffstage: false), findsOneWidget,
          reason: text);
    }
    // The page did not jump back to the top.
    expect(_scroll(tester).pixels, greaterThan(0));
  });

  testWidgets('deleting a comment on page 2 keeps the other loaded pages',
      (tester) async {
    final thread = _Thread(25);
    final client = await _mount(tester, thread);
    await _loadPageTwo(tester);

    client.setHandler('DELETE', 'comments/c-0024', (_) {
      thread.deleted.add('c-0024');
      return null;
    });
    await tester.scrollUntilVisible(find.text('C-24'), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    final y = tester.getCenter(find.text('C-24')).dy;
    final menus = find.byIcon(Icons.more_vert);
    var closest = menus.first;
    var best = double.infinity;
    for (var i = 0; i < menus.evaluate().length; i++) {
      final d = (tester.getCenter(menus.at(i)).dy - y).abs();
      if (d < best) {
        best = d;
        closest = menus.at(i);
      }
    }
    await tester.tap(closest);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete comment'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.text('C-24', skipOffstage: false), findsNothing);
    for (final text in ['C-21', 'C-23', 'C-25']) {
      expect(find.text(text, skipOffstage: false), findsOneWidget,
          reason: text);
    }
    expect(_showMore, findsNothing);
    expect(_firstPageRequests(client), 1);
    expect(_scroll(tester).pixels, greaterThan(0));
  });
}
