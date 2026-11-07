// AUTH-204: comment and reply notifications open the publication at its
// discussion, also when the discussion loads after the publication.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mushukistan_frontend/core/network/api_client.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';
import 'package:mushukistan_frontend/features/adoption_posts/presentation/screens/adoption_post_detail_screen.dart';
import 'package:mushukistan_frontend/features/auth/application/auth_controller.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_models.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_repository.dart';
import 'package:mushukistan_frontend/features/comments/presentation/screens/comments_screen.dart';
import 'package:mushukistan_frontend/features/lost_pets/presentation/screens/lost_pet_detail_screen.dart';
import 'package:mushukistan_frontend/features/notifications/data/notification_api.dart';
import 'package:mushukistan_frontend/features/notifications/presentation/notification_center_screen.dart';
import 'package:mushukistan_frontend/features/posts/presentation/screens/post_detail_screen.dart';

import '../../support/fakes.dart';

const _postId = '22222222-2222-4222-8222-222222222222';
const _petId = '33333333-3333-4333-8333-333333333333';
const _adoptionId = '44444444-4444-4444-8444-444444444444';
const _commentId = '55555555-5555-4555-8555-555555555555';

final _longText = List.filled(40, 'Synthetic detail line.').join(' ');

Map<String, Object?> _author() => {'id': 'owner-1', 'name': 'Owner'};

Map<String, Object?> _post({String kind = 'observation'}) => {
      'id': _postId,
      'cat': {'id': 'cat-1', 'status': 'unknown', 'name': 'Synthetic cat'},
      'author': _author(),
      'photo_url': 'https://example.com/cat.jpg',
      'photo_urls': ['https://example.com/cat.jpg'],
      'location': null,
      'description': _longText,
      'kind': kind,
      'created_at': '2026-10-01T00:00:00Z',
      'like_count': 0,
      'comment_count': 1,
      'is_liked_by_me': false,
    };

Map<String, Object?> _pet({bool resolved = false}) => {
      'id': _petId,
      'pet_name': 'Synthetic pet',
      'author': _author(),
      'photo_url': 'https://example.com/pet.jpg',
      'photo_urls': ['https://example.com/pet.jpg'],
      'last_seen_location': {'latitude': 41.3, 'longitude': 69.25},
      'created_at': '2026-09-28T09:00:00Z',
      'is_resolved': resolved,
      'comment_count': 1,
      'additional_info': _longText,
    };

Map<String, Object?> _adoption({bool resolved = false}) => {
      'id': _adoptionId,
      'pet_name': 'Synthetic pet',
      'author': _author(),
      'photo_url': 'https://example.com/pet.jpg',
      'photo_urls': ['https://example.com/pet.jpg'],
      'created_at': '2026-09-28T09:00:00Z',
      'is_resolved': resolved,
      'comment_count': 1,
      'description': _longText,
    };

Map<String, Object?> _comments(int count) => {
      'items': [
        for (var i = 0; i < count; i++)
          {
            'id': i == 0 ? _commentId : 'comment-$i',
            'user': {'id': 'viewer-$i', 'name': 'Commenter $i'},
            'content': 'Synthetic comment $i',
            'created_at': '2026-10-02T00:00:00Z',
          },
      ],
      'next_cursor': null,
      'limit': 20,
    };

/// The fake client with the discussion answered by [comments] (to delay it).
FakeApiClient _client({
  String postKind = 'observation',
  bool resolved = false,
  FutureOr<Object?> Function()? comments,
}) {
  final client = FakeApiClient();
  final discussion = comments ?? () => _comments(3);
  client.setHandler('GET', 'posts/$_postId', (_) => _post(kind: postKind));
  client.setHandler(
      'GET', 'lost-pets/$_petId', (_) => _pet(resolved: resolved));
  client.setHandler('GET', 'adoption-posts/$_adoptionId',
      (_) => _adoption(resolved: resolved));
  for (final path in [
    'posts/$_postId/comments',
    'lost-pets/$_petId/comments',
    'adoption-posts/$_adoptionId/comments',
  ]) {
    client.setHandler('GET', path, (_) => discussion());
  }
  for (final path in ['posts/$_postId/views', 'lost-pets/$_petId/views']) {
    client.setHandler('POST', path, (_) => null);
  }
  return client;
}

bool _focus(GoRouterState state) =>
    state.uri.queryParameters['comments'] == '1';

Future<GoRouter> _mount(WidgetTester tester, MushukistanApiClient client,
    {List<Override> extra = const []}) async {
  tester.view.physicalSize = const Size(390, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(initialLocation: '/inbox', routes: [
    GoRoute(
      path: '/inbox',
      builder: (_, __) => const Scaffold(body: Text('Inbox')),
    ),
    GoRoute(
      path: '/notifications',
      builder: (_, __) => const NotificationCenterScreen(),
    ),
    GoRoute(
      path: '/posts/:id',
      builder: (_, state) => PostDetailScreen(
          postId: state.pathParameters['id']!, focusComments: _focus(state)),
    ),
    GoRoute(
      path: '/lost-pets/:id',
      builder: (_, state) => LostPetDetailScreen(
          lostPetId: state.pathParameters['id']!, focusComments: _focus(state)),
    ),
    GoRoute(
      path: '/adoption-posts/:id',
      builder: (_, state) => AdoptionPostDetailScreen(
          adoptionPostId: state.pathParameters['id']!,
          focusComments: _focus(state)),
    ),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      mushukistanApiProvider.overrideWithValue(MushukistanApi(client: client)),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(
        restoreResult: SessionRestoreSuccess(AuthSession.restored(
            accessToken: 'token', user: testUser(id: 'owner-1'))),
      )),
      googleIdentityTokenProvider
          .overrideWithValue(FakeGoogleIdentityTokenProvider()),
      ...extra,
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return router;
}

/// Vertical position of the discussion's top in the viewport (0 = top).
double _discussionTop(WidgetTester tester) =>
    tester.getTopLeft(find.byType(CommentDeepLinkFocus)).dy;

ScrollPosition _page(WidgetTester tester) => tester
    .state<ScrollableState>(find
        .ancestor(
            of: find.byType(CommentDeepLinkFocus),
            matching: find.byType(Scrollable))
        .first)
    .position;

double _pageOffset(WidgetTester tester) => _page(tester).pixels;

/// Pumps (without settling: the discussion spinner animates) until the
/// publication has loaded and its discussion section is built.
Future<void> _waitForPublication(WidgetTester tester) async {
  for (var i = 0; i < 100; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (find.byType(CommentDeepLinkFocus).evaluate().isNotEmpty) {
      await tester.pump(const Duration(milliseconds: 500));
      return;
    }
  }
  fail('publication did not load');
}

/// The discussion heading sits in the upper part of the screen, below the
/// app bar, instead of far below the visible area. A short page cannot scroll
/// past its end: then it is scrolled to the end, with the discussion visible.
void _expectDiscussionInView(WidgetTester tester) {
  final page = _page(tester);
  expect(page.pixels, greaterThan(0));
  final top = _discussionTop(tester);
  expect(top, greaterThanOrEqualTo(kToolbarHeight - 1));
  if (page.pixels < page.maxScrollExtent - 1) {
    expect(top, lessThan(800 * 0.3));
  } else {
    expect(top, lessThan(800 - 150));
  }
}

void main() {
  for (final (name, path) in [
    ('ordinary post', '/posts/$_postId'),
    ('Lost Pet', '/lost-pets/$_petId'),
    ('Adoption', '/adoption-posts/$_adoptionId'),
  ]) {
    testWidgets('$name: waits for a delayed discussion, then shows it',
        (tester) async {
      final pending = Completer<Object?>();
      final router =
          await _mount(tester, _client(comments: () => pending.future));
      router.push('$path?comments=1');
      await _waitForPublication(tester);
      // Publication shown, discussion still loading: nothing jumps yet.
      expect(_pageOffset(tester), 0);

      pending.complete(_comments(20));
      await tester.pumpAndSettle();
      _expectDiscussionInView(tester);
      expect(find.text('Synthetic comment 0'), findsOneWidget);

      // Back returns to where the user came from, with no extra screens.
      router.pop();
      await tester.pumpAndSettle();
      expect(find.text('Inbox'), findsOneWidget);
      expect(find.byType(CommentDeepLinkFocus), findsNothing);
    });

    testWidgets('$name: without the comments link the page opens at the top',
        (tester) async {
      final router = await _mount(tester, _client());
      router.push(path);
      await tester.pumpAndSettle();
      expect(_pageOffset(tester), 0);
    });
  }

  testWidgets('Needs Help post opens at its discussion', (tester) async {
    final router = await _mount(tester, _client(postKind: 'needs_help'));
    router.push('/posts/$_postId?comments=1');
    await tester.pumpAndSettle();
    _expectDiscussionInView(tester);
  });

  testWidgets('resolved Lost Pet and Adoption still open at the discussion',
      (tester) async {
    final router = await _mount(tester, _client(resolved: true));
    router.push('/lost-pets/$_petId?comments=1');
    await tester.pumpAndSettle();
    _expectDiscussionInView(tester);
    router.pop();
    await tester.pumpAndSettle();
    router.push('/adoption-posts/$_adoptionId?comments=1');
    await tester.pumpAndSettle();
    _expectDiscussionInView(tester);
  });

  testWidgets('empty discussion (comment since deleted) still lands there',
      (tester) async {
    final router = await _mount(tester, _client(comments: () => _comments(0)));
    router.push('/lost-pets/$_petId?comments=1');
    await tester.pumpAndSettle();
    _expectDiscussionInView(tester);
  });

  testWidgets('discussion that fails to load still shows its section',
      (tester) async {
    final router = await _mount(
        tester, _client(comments: () => throw StateError('offline')));
    router.push('/adoption-posts/$_adoptionId?comments=1');
    await tester.pumpAndSettle();
    _expectDiscussionInView(tester);
  });

  testWidgets('a user who scrolls while it loads is not moved', (tester) async {
    final pending = Completer<Object?>();
    final router =
        await _mount(tester, _client(comments: () => pending.future));
    router.push('/lost-pets/$_petId?comments=1');
    await _waitForPublication(tester);
    await tester.drag(
        find.byType(SingleChildScrollView).first, const Offset(0, -120));
    await tester.pump(const Duration(seconds: 1));
    final reading = _pageOffset(tester);
    expect(reading, greaterThan(0));
    pending.complete(_comments(5));
    await tester.pumpAndSettle();
    expect(_pageOffset(tester), reading);
  });

  group('from the Notification Center', () {
    for (final (kind, targetKind, targetId) in [
      ('comment', 'lost_pet', _petId),
      ('comment', 'adoption_post', _adoptionId),
      ('comment', 'post', _postId),
      ('reply', 'post', _postId),
    ]) {
      testWidgets('$kind on $targetKind opens its discussion and reads it',
          (tester) async {
        final client = _client();
        var marked = 0;
        client.setHandler(
            'GET',
            'notifications',
            (_) => {
                  'items': [
                    {
                      'id': '11111111-1111-4111-8111-111111111111',
                      'kind': kind,
                      'actor_name': 'Synthetic actor',
                      'target_kind': targetKind,
                      'target_id': targetId,
                      'comment_id': _commentId,
                      'created_at': '2026-10-07T12:00:00Z',
                      'read_at': null,
                    },
                  ],
                  'next_cursor': null,
                  'limit': 20,
                });
        client.setHandler(
            'POST', 'notifications/11111111-1111-4111-8111-111111111111/read',
            (_) {
          marked++;
          return null;
        });
        client.setHandler(
            'GET', 'notifications/unread-count', (_) => {'count': 0});
        final router = await _mount(tester, client, extra: [
          notificationApiProvider.overrideWithValue(NotificationApi(client)),
        ]);
        router.push('/notifications');
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('Synthetic actor'));
        await tester.pumpAndSettle();
        expect(marked, 1);
        _expectDiscussionInView(tester);

        router.pop();
        await tester.pumpAndSettle();
        expect(find.byType(NotificationCenterScreen), findsOneWidget);
        expect(find.byType(CommentDeepLinkFocus), findsNothing);
      });
    }
  });
}
