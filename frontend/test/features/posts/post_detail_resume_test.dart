import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/core/lifecycle/app_resume.dart';
import 'package:mushukistan_frontend/core/network/api_client.dart';
import 'package:mushukistan_frontend/core/network/api_error.dart';
import 'package:mushukistan_frontend/features/auth/application/auth_controller.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_models.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_repository.dart';
import 'package:mushukistan_frontend/features/posts/presentation/screens/post_detail_screen.dart';

import '../../support/fakes.dart';

class _PostServer {
  String description = 'Spotted near the park.';
  bool offline = false;

  void install(FakeApiClient client) {
    client
      ..setHandler('GET', 'posts/post-1', (_) {
        if (offline) {
          throw const MushukistanApiException(
            kind: ApiFailureKind.network,
            code: 'NETWORK_ERROR',
            message: 'offline',
          );
        }
        return {
          'id': 'post-1',
          'cat': {'id': 'cat-1', 'name': 'Mushu', 'status': 'healthy'},
          'author': {'id': 'author-2', 'name': 'Amina'},
          'photo_url': 'invalid:',
          'photo_urls': ['invalid:'],
          'description': description,
          'created_at': '2026-07-01T10:00:00.000Z',
          'like_count': 3,
          'comment_count': 0,
          'is_liked_by_me': false,
          'is_public': true,
        };
      })
      ..setHandler('GET', 'posts/post-1/comments', (_) {
        if (offline) {
          throw const MushukistanApiException(
            kind: ApiFailureKind.network,
            code: 'NETWORK_ERROR',
            message: 'offline',
          );
        }
        return {'items': <Object?>[], 'next_cursor': null, 'limit': 20};
      })
      ..setHandler('POST', 'posts/post-1/views', (_) => null);
  }
}

Future<(ProviderContainer, FakeApiClient, void Function(Duration))> _pump(
    WidgetTester tester, _PostServer server) async {
  tester.view.physicalSize = const Size(390, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final client = FakeApiClient();
  server.install(client);
  var now = const Duration(hours: 1);
  final container = ProviderContainer(overrides: [
    apiClientProvider.overrideWithValue(client),
    authRepositoryProvider.overrideWithValue(FakeAuthRepository(
      restoreResult: SessionRestoreSuccess(
        AuthSession.restored(accessToken: 'token', user: testUser()),
      ),
    )),
    googleIdentityTokenProvider
        .overrideWithValue(FakeGoogleIdentityTokenProvider()),
    monotonicClockProvider.overrideWithValue(() => now),
  ]);
  addTearDown(container.dispose);
  await container.read(authControllerProvider.notifier).restoreSession();
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: PostDetailScreen(postId: 'post-1')),
  ));
  await tester.pumpAndSettle();

  void awayFor(Duration duration) {
    final tracker = container.read(appResumeProvider.notifier);
    tracker.handleLifecycle(AppLifecycleState.paused);
    now += duration;
    tracker.handleLifecycle(AppLifecycleState.resumed);
  }

  return (container, client, awayFor);
}

int _postRequests(FakeApiClient client) =>
    client.calls.where((c) => c.path == 'posts/post-1').length;

void main() {
  testWidgets('back after 5 minutes: the post reloads, the draft stays',
      (tester) async {
    final server = _PostServer();
    final (_, client, awayFor) = await _pump(tester, server);
    expect(find.text('Spotted near the park.'), findsOneWidget);
    final field = find.byType(TextField).last;
    await tester.enterText(field, 'My unsent comment');
    final requests = _postRequests(client);

    server.description = 'Now sleeping by the door.';
    awayFor(const Duration(minutes: 1));
    await tester.pumpAndSettle();
    expect(_postRequests(client), requests);

    awayFor(const Duration(minutes: 5));
    await tester.pumpAndSettle();
    expect(_postRequests(client), requests + 1);
    expect(find.text('Now sleeping by the door.'), findsOneWidget);
    expect(find.text('My unsent comment'), findsOneWidget);
  });

  testWidgets('offline: the post already shown stays, no error page',
      (tester) async {
    final server = _PostServer();
    final (_, client, awayFor) = await _pump(tester, server);
    await tester.enterText(find.byType(TextField).last, 'Draft');
    final requests = _postRequests(client);
    server.offline = true;

    awayFor(const Duration(minutes: 20));
    await tester.pumpAndSettle();
    expect(_postRequests(client), requests + 1);
    expect(find.text('Spotted near the park.'), findsOneWidget);
    expect(find.text('Draft'), findsOneWidget);
  });
}
