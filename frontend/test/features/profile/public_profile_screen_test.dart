import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mushukistan_frontend/core/network/api_client.dart';
import 'package:mushukistan_frontend/core/network/api_error.dart';
import 'package:mushukistan_frontend/features/feed/presentation/screens/feed_screen.dart';
import 'package:mushukistan_frontend/features/auth/application/auth_controller.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_models.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_repository.dart';
import 'package:mushukistan_frontend/features/profile/presentation/screens/public_profile_screen.dart';
import 'package:mushukistan_frontend/features/profile/presentation/widgets/profile_components.dart';

import '../../support/fakes.dart';

void main() {
  Future<(FakeApiClient, ProviderContainer, GoRouter)> mount(
    WidgetTester tester, {
    required bool publicActivity,
    bool authenticated = false,
    bool withPost = true,
    int postCount = 1,
    bool privatePostsResponse = false,
    String? avatarUrl,
  }) async {
    final client = FakeApiClient();
    client.setHandler(
        'GET',
        'users/other',
        (_) => {
              'id': 'other',
              'name': 'Sardor Contributor',
              'avatar_url': avatarUrl,
              'bio': 'Looks after local cats',
              'registered_at': '2026-07-01T10:00:00Z',
              'observation_count': 12,
              'total_likes_received': 45,
              'comment_count': 17,
              'allow_public_activity_view': publicActivity,
              'email': 'private@example.com',
              'phone_number': '+998901234567',
              'telegram_username': 'private_handle',
            });
    client.setHandler('GET', 'users/other/posts', (_) {
      if (privatePostsResponse) {
        throw const MushukistanApiException(
          kind: ApiFailureKind.forbidden,
          code: 'ACTIVITY_PRIVATE',
          message: 'Private activity',
          statusCode: 403,
        );
      }
      return {
        'items': withPost
            ? List.generate(
                postCount,
                (index) => {
                      'id': 'post-${index + 1}',
                      'cat': {
                        'id': 'cat-1',
                        'name': 'Momiq',
                        'status': 'unknown'
                      },
                      'author': {'id': 'other', 'name': 'Sardor Contributor'},
                      'photo_url': 'invalid:',
                      'photo_urls': <String>[],
                      'description': 'Seen near the park. '.padRight(720, 'c'),
                      'kind': 'needs_help',
                      'created_at': '2026-09-01T10:00:00Z',
                      'like_count': 2,
                      'comment_count': 1,
                      'is_liked_by_me': false,
                    })
            : <Object>[],
        'limit': 4,
      };
    });
    client.setHandler('POST', 'users/other/block', (_) => null);
    final container = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(client),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(
        restoreResult: authenticated
            ? SessionRestoreSuccess(
                AuthSession.restored(accessToken: 'token', user: testUser()))
            : const SessionRestoreMissing(),
      )),
      googleIdentityTokenProvider.overrideWithValue(
        FakeGoogleIdentityTokenProvider(),
      ),
    ]);
    await container.read(authControllerProvider.notifier).restoreSession();
    final router = GoRouter(initialLocation: '/users/other', routes: [
      GoRoute(
        path: '/users/:userId',
        builder: (_, state) =>
            PublicProfileScreen(userId: state.pathParameters['userId']!),
      ),
      GoRoute(
        path: '/users/:userId/observations',
        builder: (_, __) => const Scaffold(body: Text('Observations route')),
      ),
      GoRoute(
        path: '/users/:userId/comments',
        builder: (_, __) => const Scaffold(body: Text('Comments route')),
      ),
      GoRoute(
        path: '/posts/:postId',
        builder: (_, __) => const Scaffold(body: Text('Post detail route')),
      ),
      GoRoute(
        path: '/report',
        builder: (_, __) => const Scaffold(body: Text('Report route')),
      ),
      GoRoute(
        path: '/auth-required',
        builder: (_, __) => const Scaffold(body: Text('Sign in required')),
      ),
    ]);
    addTearDown(container.dispose);
    addTearDown(router.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();
    return (client, container, router);
  }

  testWidgets('public summary and recent Feed post hide private fields',
      (tester) async {
    tester.view.physicalSize = const Size(390, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final (client, _, _) = await mount(tester, publicActivity: true);

    expect(find.text('Sardor Contributor'), findsWidgets);
    expect(find.text('Looks after local cats'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('45'), findsOneWidget);
    expect(find.text('17'), findsOneWidget);
    expect(find.text('Recent observations'), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, -450));
    await tester.pumpAndSettle();
    expect(find.textContaining('Momiq', findRichText: true), findsOneWidget);
    expect(find.text('private@example.com'), findsNothing);
    expect(find.text('+998901234567'), findsNothing);
    expect(find.text('private_handle'), findsNothing);
    expect(
        client.calls
            .where((call) => call.path == 'users/other/posts')
            .single
            .queryParameters?['limit'],
        4);
    expect(tester.takeException(), isNull);

    await tester.tap(find.textContaining('Momiq', findRichText: true));
    await tester.pumpAndSettle();
    expect(find.text('Post detail route'), findsOneWidget);
  });

  testWidgets('private activity keeps identity but skips preview request',
      (tester) async {
    final (client, _, _) = await mount(tester, publicActivity: false);

    expect(find.text('Sardor Contributor'), findsOneWidget);
    expect(find.text('This user has hidden their activity.'), findsOneWidget);
    expect(find.text('Momiq'), findsNothing);
    expect(client.calls.where((call) => call.path == 'users/other/posts'),
        isEmpty);
    await tester.tap(find.text('12'));
    await tester.pumpAndSettle();
    expect(find.text('Observations route'), findsNothing);
  });

  testWidgets('wide profile keeps summary fixed while recent posts scroll',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mount(tester, publicActivity: true, postCount: 4);

    final summary = find.byType(ProfileSummaryCard);
    expect(summary, findsOneWidget);
    expect(find.byType(ListView), findsOneWidget);
    final summaryTopBefore = tester.getTopLeft(summary).dy;
    final firstPostTopBefore =
        tester.getTopLeft(find.byType(FeedPostCard).first).dy;
    await tester.drag(find.byType(ListView).first, const Offset(0, -560));
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(summary).dy, summaryTopBefore);
    expect(tester.getTopLeft(find.byType(FeedPostCard).first).dy,
        lessThan(firstPostTopBefore));
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact profile keeps a single vertical scroll region',
      (tester) async {
    tester.view.physicalSize = const Size(390, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mount(tester, publicActivity: true, postCount: 4);

    expect(find.byType(ListView), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, -560));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileSummaryCard), findsNothing);
    expect(find.byType(FeedPostCard), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('privacy response hides a stale activity preview',
      (tester) async {
    final (client, _, _) = await mount(
      tester,
      publicActivity: true,
      privatePostsResponse: true,
    );
    expect(find.text('This user has hidden their activity.'), findsOneWidget);
    expect(find.text('See all'), findsNothing);
    expect(client.calls.where((call) => call.path == 'users/other/posts'),
        hasLength(1));
  });

  testWidgets('guest block action uses the sign-in flow', (tester) async {
    final (client, _, _) = await mount(tester, publicActivity: false);
    await tester.tap(find.byTooltip('Profile actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Block user'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in required'), findsOneWidget);
    expect(client.calls.where((call) => call.path == 'users/other/block'),
        isEmpty);
  });

  testWidgets('report and block stay in overflow; block is disabled after use',
      (tester) async {
    final (client, _, _) = await mount(
      tester,
      publicActivity: true,
      authenticated: true,
      withPost: false,
    );
    await tester.tap(find.byTooltip('Profile actions'));
    await tester.pumpAndSettle();
    expect(find.text('Report'), findsOneWidget);
    expect(find.text('Block user'), findsOneWidget);
    await tester.tap(find.text('Block user'));
    await tester.pumpAndSettle();
    expect(find.text('Block user?'), findsOneWidget);
    await tester.tap(find.text('Block', skipOffstage: false));
    await tester.pumpAndSettle();
    expect(client.calls.where((call) => call.path == 'users/other/block'),
        hasLength(1));

    await tester.tap(find.byTooltip('Profile actions'));
    await tester.pumpAndSettle();
    final blockItem = tester
        .widgetList<PopupMenuItem>(
          find.byWidgetPredicate((widget) => widget is PopupMenuItem),
        )
        .last;
    expect(blockItem.enabled, isFalse);
    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();
    expect(find.text('Report route'), findsOneWidget);
  });

  testWidgets('missing and broken avatars show initials', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: ProfileAvatar(name: 'Sardor Muxtorov')),
    ));
    expect(find.text('SM'), findsOneWidget);
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: ProfileAvatar(name: 'Sardor Muxtorov', avatarUrl: 'invalid:'),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('SM'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
