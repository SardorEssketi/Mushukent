import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/core/network/api_error.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';
import 'package:mushukistan_frontend/features/auth/application/auth_controller.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_repository.dart';
import 'package:mushukistan_frontend/features/feed/presentation/screens/feed_screen.dart';

import '../../support/fakes.dart';

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

  testWidgets('feed post cards omit the publication date', (tester) async {
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

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mushukistanApiProvider.overrideWithValue(
            MushukistanApi(client: apiClient),
          ),
        ],
        child: const MaterialApp(home: FeedScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Recent'), findsNothing);

    await tester.tap(find.text('Popular'));
    await tester.pumpAndSettle();
    expect(apiClient.calls.last.queryParameters?['filter'], 'popular');

    await tester.tap(find.text('Popular'));
    await tester.pumpAndSettle();
    expect(apiClient.calls.last.queryParameters?['filter'], 'recent');
  });
}
