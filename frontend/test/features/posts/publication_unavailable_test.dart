// AUTH-218: a publication that is definitively unavailable shows a neutral
// terminal state with a way to the Feed, not an endless Retry; recoverable
// failures keep Retry.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mushukistan_frontend/core/localization/language_controller.dart';
import 'package:mushukistan_frontend/core/network/api_client.dart';
import 'package:mushukistan_frontend/core/network/api_error.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';
import 'package:mushukistan_frontend/core/storage/token_store.dart';
import 'package:mushukistan_frontend/features/adoption_posts/presentation/screens/adoption_post_detail_screen.dart';
import 'package:mushukistan_frontend/features/auth/application/auth_controller.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_models.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_repository.dart';
import 'package:mushukistan_frontend/features/lost_pets/presentation/screens/lost_pet_detail_screen.dart';
import 'package:mushukistan_frontend/features/posts/presentation/screens/post_detail_screen.dart';

import '../../support/fakes.dart';

const _id = '3f709efe-7c16-478b-bc8e-eb2d10e1c06b';

/// (label, detail path prefix, API path prefix, documented not-found code)
const _types = [
  ('post', '/posts', 'posts', 'POST_NOT_FOUND'),
  ('lost pet', '/lost-pets', 'lost-pets', 'LOST_PET_NOT_FOUND'),
  ('adoption', '/adoption-posts', 'adoption-posts', 'ADOPTION_POST_NOT_FOUND'),
];

MushukistanApiException _notFound(String code) => MushukistanApiException(
    kind: ApiFailureKind.notFound,
    statusCode: 404,
    code: code,
    message: 'Not found.');

const _network = MushukistanApiException(
    kind: ApiFailureKind.network, code: 'NETWORK_ERROR', message: 'Offline.');

const _server = MushukistanApiException(
    kind: ApiFailureKind.server,
    statusCode: 500,
    code: 'INTERNAL_ERROR',
    message: 'Server error.');

Map<String, Object?> _detail(String apiPrefix) => switch (apiPrefix) {
      'posts' => {
          'id': _id,
          'cat': {'id': 'cat-1', 'status': 'unknown', 'name': 'Synthetic cat'},
          'author': {'id': 'owner-1', 'name': 'Owner'},
          'photo_url': 'https://example.com/cat.jpg',
          'photo_urls': ['https://example.com/cat.jpg'],
          'kind': 'observation',
          'created_at': '2026-10-01T00:00:00Z',
          'like_count': 0,
          'comment_count': 0,
          'is_liked_by_me': false,
        },
      _ => {
          'id': _id,
          'pet_name': 'Synthetic pet',
          'author': {'id': 'owner-1', 'name': 'Owner'},
          'photo_url': 'https://example.com/pet.jpg',
          'photo_urls': ['https://example.com/pet.jpg'],
          'created_at': '2026-09-28T09:00:00Z',
          'is_resolved': false,
          'comment_count': 0,
        },
    };

Future<GoRouter> _mount(
  WidgetTester tester,
  MushukistanApiClient client, {
  required String path,
  bool signedIn = true,
  AppLanguage language = AppLanguage.english,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(initialLocation: '/feed', routes: [
    GoRoute(
        path: '/feed',
        builder: (_, __) => const Scaffold(body: Text('Feed root'))),
    GoRoute(
        path: '/posts/:id',
        builder: (_, s) => PostDetailScreen(postId: s.pathParameters['id']!)),
    GoRoute(
        path: '/lost-pets/:id',
        builder: (_, s) =>
            LostPetDetailScreen(lostPetId: s.pathParameters['id']!)),
    GoRoute(
        path: '/adoption-posts/:id',
        builder: (_, s) =>
            AdoptionPostDetailScreen(adoptionPostId: s.pathParameters['id']!)),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      mushukistanApiProvider.overrideWithValue(MushukistanApi(client: client)),
      authRepositoryProvider.overrideWithValue(signedIn
          ? FakeAuthRepository(
              restoreResult: SessionRestoreSuccess(AuthSession.restored(
                  accessToken: 'token', user: testUser(id: 'viewer-1'))))
          : FakeAuthRepository()),
      googleIdentityTokenProvider
          .overrideWithValue(FakeGoogleIdentityTokenProvider()),
      appLanguageProvider.overrideWith((ref) => language),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  router.push(path);
  await tester.pumpAndSettle();
  return router;
}

FakeApiClient _client(String apiPrefix, Object? Function() detail) {
  final client = FakeApiClient();
  client.setHandler('GET', '$apiPrefix/$_id', (_) => detail());
  client.setHandler('GET', '$apiPrefix/$_id/comments',
      (_) => {'items': <Object>[], 'next_cursor': null, 'limit': 20});
  client.setHandler('POST', '$apiPrefix/$_id/views', (_) => null);
  return client;
}

int _detailReads(FakeApiClient client, String apiPrefix) => client.calls
    .where((c) => c.method == 'GET' && c.path == '$apiPrefix/$_id')
    .length;

void _expectUnavailable() {
  expect(find.text('This publication is not available'), findsOneWidget);
  expect(find.text('It may have been removed or is no longer visible to you.'),
      findsOneWidget);
  expect(find.widgetWithText(FilledButton, 'Go to Feed'), findsOneWidget);
  expect(find.text('Retry'), findsNothing);
  expect(find.text('Could not load this section'), findsNothing);
}

void main() {
  for (final (label, route, api, code) in _types) {
    // Deleted by its owner, removed by a moderator, never existed, private or
    // hidden by a block: the API answers each with the same 404 and code, so
    // the app shows the same neutral state and reveals no reason.
    for (final scenario in [
      'moderator-removed',
      'owner-deleted',
      'nonexistent id',
      'private',
      'blocked author',
    ]) {
      testWidgets('$label, $scenario: neutral unavailable state, Go to Feed',
          (tester) async {
        final client = _client(api, () => throw _notFound(code));
        final router = await _mount(tester, client, path: '$route/$_id');
        _expectUnavailable();
        final reads = _detailReads(client, api);
        await tester.tap(find.widgetWithText(FilledButton, 'Go to Feed'));
        await tester.pumpAndSettle();
        expect(find.text('Feed root'), findsOneWidget);
        expect(router.canPop(), isFalse);
        expect(_detailReads(client, api), reads, reason: 'no retry loop');
      });
    }

    testWidgets('$label: Back from the unavailable state returns',
        (tester) async {
      final client = _client(api, () => throw _notFound(code));
      final router = await _mount(tester, client, path: '$route/$_id');
      _expectUnavailable();
      router.pop();
      await tester.pumpAndSettle();
      expect(find.text('Feed root'), findsOneWidget);
    });

    testWidgets('$label: guest deep link gets the same neutral state',
        (tester) async {
      final client = _client(api, () => throw _notFound(code));
      await _mount(tester, client, path: '$route/$_id', signedIn: false);
      _expectUnavailable();
    });

    testWidgets('$label: network outage keeps Retry and recovers',
        (tester) async {
      var online = false;
      final client = _client(api, () {
        if (!online) throw _network;
        return _detail(api);
      });
      await _mount(tester, client, path: '$route/$_id');
      expect(find.text('Could not load this section'), findsOneWidget);
      expect(find.text('This publication is not available'), findsNothing);
      online = true;
      await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Could not load this section'), findsNothing);
      expect(find.textContaining('Synthetic'), findsWidgets);
    });

    testWidgets('$label: server error keeps Retry', (tester) async {
      final client = _client(api, () => throw _server);
      await _mount(tester, client, path: '$route/$_id');
      expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);
      expect(find.text('This publication is not available'), findsNothing);
    });
  }

  testWidgets(
      'a 404 without the endpoint code (proxy, old server) is retryable',
      (tester) async {
    final client = _client('posts', () => throw _notFound('NOT_FOUND'));
    await _mount(tester, client, path: '/posts/$_id');
    expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);
  });

  testWidgets('a malformed id (validation error) is unavailable, not retried',
      (tester) async {
    final client = _client(
        'posts',
        () => throw const MushukistanApiException(
            kind: ApiFailureKind.validation,
            statusCode: 422,
            code: 'VALIDATION_ERROR',
            message: 'Invalid id.'));
    await _mount(tester, client, path: '/posts/$_id');
    _expectUnavailable();
  });

  testWidgets('localized in Russian and Uzbek', (tester) async {
    final client = _client('posts', () => throw _notFound('POST_NOT_FOUND'));
    await _mount(tester, client,
        path: '/posts/$_id', language: AppLanguage.russian);
    expect(find.text('Публикация недоступна'), findsOneWidget);
    expect(find.text('Перейти в ленту'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await _mount(tester, client,
        path: '/posts/$_id', language: AppLanguage.uzbek);
    expect(find.text('Bu nashr mavjud emas'), findsOneWidget);
    expect(find.text('Lentaga o‘tish'), findsOneWidget);
  });

  testWidgets('the real HTTP client maps the backend 404 body to this state',
      (tester) async {
    final dio = Dio(BaseOptions(
        baseUrl: 'https://example.test/api/v1/', validateStatus: (_) => true))
      ..httpClientAdapter = _NotFoundAdapter();
    final client =
        DioMushukistanApiClient(dio: dio, tokenStore: InMemoryAuthTokenStore());
    await _mount(tester, client, path: '/posts/$_id', signedIn: false);
    _expectUnavailable();
  });
}

/// Answers every request like the backend does for a removed post.
class _NotFoundAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    return ResponseBody.fromString(
      jsonEncode({
        'success': false,
        'error': {'code': 'POST_NOT_FOUND', 'message': 'Post not found.'},
      }),
      404,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
