import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/core/network/api_error.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';
import 'package:mushukistan_frontend/core/navigation/tab_actions.dart';
import 'package:mushukistan_frontend/core/localization/language_controller.dart';
import 'package:mushukistan_frontend/features/auth/application/auth_controller.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_repository.dart';
import 'package:mushukistan_frontend/features/feed/presentation/screens/feed_screen.dart';

import '../../support/fakes.dart';

Future<ProviderContainer> _screenContainer(
  FakeApiClient apiClient, {
  AppLanguage language = AppLanguage.english,
}) async {
  final container = ProviderContainer(overrides: [
    mushukistanApiProvider.overrideWithValue(
      MushukistanApi(client: apiClient),
    ),
    authRepositoryProvider.overrideWithValue(
      FakeAuthRepository(restoreResult: const SessionRestoreMissing()),
    ),
    googleIdentityTokenProvider.overrideWithValue(
      FakeGoogleIdentityTokenProvider(),
    ),
    appLanguageProvider.overrideWith((ref) => language),
  ]);
  await container.read(authControllerProvider.notifier).restoreSession();
  return container;
}

void main() {
  testWidgets('backend failure keeps the public feed shell and retry action',
      (tester) async {
    final apiClient = FakeApiClient();
    apiClient.setHandler('GET', 'feed', (_) {
      throw const MushukistanApiException(
        kind: ApiFailureKind.network,
        code: 'NETWORK_ERROR',
        message: 'Backend unavailable.',
      );
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mushukistanApiProvider.overrideWithValue(
            MushukistanApi(client: apiClient),
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
        child: const MaterialApp(home: FeedScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Feed'), findsOneWidget);
    expect(find.text('Could not load this section'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);
  });

  testWidgets('feed post cards show author and compact publication date',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final post = PostSummary(
      id: 'post-1',
      cat: const PostCatData(
        id: 'cat-1',
        status: 'healthy',
        name: 'Milo',
      ),
      author: const PostAuthorData(name: 'Amina'),
      photoUrl: 'https://example.com/cat.jpg',
      photoUrls: const ['https://example.com/cat.jpg'],
      location: null,
      createdAt: DateTime.utc(2026, 8, 14),
      likeCount: 1,
      commentCount: 2,
      isLikedByMe: false,
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: FeedPostCard(post: post, onTap: () {}),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Published: 2026-08-14'), findsNothing);
    expect(find.text('Amina'), findsOneWidget);
    expect(find.byType(FeedPostCard), findsOneWidget);
  });

  testWidgets('feed card distinguishes a needs-help observation by kind',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final post = PostSummary(
      id: 'post-help',
      cat: const PostCatData(id: 'cat-1', status: 'unknown', name: 'Milo'),
      photoUrl: 'https://example.com/cat.jpg',
      photoUrls: const ['https://example.com/cat.jpg'],
      location: const GeoPoint(latitude: 41.31, longitude: 69.28),
      createdAt: DateTime.utc(2026, 9, 21),
      likeCount: 0,
      commentCount: 0,
      isLikedByMe: false,
      kind: 'needs_help',
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: FeedPostCard(post: post, onTap: () {})),
      ),
    );
    await tester.pump();

    expect(find.text('Needs help'), findsOneWidget);
  });

  testWidgets('mobile feed hides Recent and toggles filters', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final apiClient = FakeApiClient();
    apiClient.setHandler('GET', 'feed', (_) {
      return <String, Object?>{
        'items': <Object?>[],
        'next_cursor': null,
        'limit': 30,
      };
    });

    final container = await _screenContainer(apiClient);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: FeedScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Recent'), findsOneWidget);
    expect(container.read(feedModeProvider), 'recent');
    await tester.tap(find.text('Recent'));
    await tester.pumpAndSettle();
    expect(container.read(feedModeProvider), 'recent');

    await tester.tap(find.text('Popular'));
    await tester.pumpAndSettle();
    expect(apiClient.calls.last.queryParameters?['filter'], 'popular');
    expect(container.read(feedModeProvider), 'popular');

    await tester.tap(find.text('Popular'));
    await tester.pumpAndSettle();
    expect(container.read(feedModeProvider), 'popular');
    expect(apiClient.calls.last.queryParameters?['filter'], 'popular');
  });

  testWidgets('long translated mobile filters stay scrollable without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final apiClient = FakeApiClient()
      ..setHandler(
          'GET',
          'feed',
          (_) => {
                'items': <Object?>[],
                'next_cursor': null,
                'limit': 30,
              });
    final container = await _screenContainer(
      apiClient,
      language: AppLanguage.russian,
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: FeedScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Новые'), findsOneWidget);
    expect(find.byType(FittedBox), findsNothing);
    expect(find.byType(SingleChildScrollView), findsWidgets);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('Потерянные питомцы'));
    expect(find.text('Потерянные питомцы'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('feed scroll-to-top requests safely move a scrolled feed home',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final apiClient = FakeApiClient()
      ..setHandler(
          'GET',
          'feed',
          (_) => {
                'items': List.generate(
                    12,
                    (index) => {
                          'id': 'post-$index',
                          'cat': {'id': 'cat-$index', 'name': 'Milo $index'},
                          'author': {'id': 'author', 'name': 'Amina'},
                          'photo_url': 'invalid:',
                          'photo_urls': <Object?>[],
                          'description': 'A neighborhood cat update',
                          'created_at': '2026-09-01T10:00:00Z',
                          'like_count': 0,
                          'comment_count': 0,
                          'is_liked_by_me': false,
                        }),
                'next_cursor': null,
                'limit': 30,
              });
    final container = await _screenContainer(apiClient);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: FeedScreen()),
    ));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -1100));
    await tester.pumpAndSettle();
    final controller = tester
        .widget<CustomScrollView>(find.byType(CustomScrollView))
        .controller!;
    expect(controller.offset, greaterThan(0));

    container.read(feedScrollToTopRequestsProvider.notifier).state++;
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expect(controller.offset, 0);
    expect(tester.takeException(), isNull);
  });
}
