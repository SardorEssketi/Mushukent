// AUTH-206: the report confirmation's Feed button opens the Feed root, not
// the reported content; Back keeps its usual behavior.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';
import 'package:mushukistan_frontend/features/moderation/presentation/screens/report_content_screen.dart';

import '../../support/fakes.dart';

const _postId = '22222222-2222-4222-8222-222222222222';

class _ReportedPost extends StatelessWidget {
  const _ReportedPost();

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Reported post detail')),
        body: TextButton(
          onPressed: () => context.push(Uri(path: '/report', queryParameters: {
            'type': 'post',
            'id': _postId,
            'label': 'Synthetic post',
          }).toString()),
          child: const Text('Report'),
        ),
      );
}

Future<(FakeApiClient, GoRouter)> _mount(
  WidgetTester tester, {
  required String initialLocation,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final client = FakeApiClient();
  // The API answers a repeated report with the existing open report.
  client.setHandler(
      'POST',
      'reports',
      (_) => {
            'id': 'report-1',
            'target_type': 'post',
            'target_id': _postId,
            'reason': 'Spam',
            'status': 'open',
            'created_at': '2026-11-01T00:00:00Z',
          });
  final router = GoRouter(initialLocation: initialLocation, routes: [
    GoRoute(
      path: '/feed',
      builder: (_, __) => Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => context.push('/posts/$_postId'),
            child: const Text('Feed root'),
          ),
        ),
      ),
    ),
    GoRoute(path: '/posts/:id', builder: (_, __) => const _ReportedPost()),
    GoRoute(
      path: '/report',
      builder: (_, state) => ReportContentScreen(
        initialTargetType: state.uri.queryParameters['type'],
        initialTargetId: state.uri.queryParameters['id'],
        initialTargetLabel: state.uri.queryParameters['label'],
      ),
    ),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      mushukistanApiProvider.overrideWithValue(MushukistanApi(client: client)),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return (client, router);
}

Future<void> _report(WidgetTester tester) async {
  await tester.tap(find.text('Report'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Spam'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Submit report'));
  await tester.pumpAndSettle();
  expect(find.text('Report submitted.'), findsOneWidget);
}

int _reportPosts(FakeApiClient client) => client.calls
    .where((call) => call.method == 'POST' && call.path == 'reports')
    .length;

void main() {
  testWidgets('report started from Feed: Feed button opens the Feed root',
      (tester) async {
    final (client, router) = await _mount(tester, initialLocation: '/feed');
    await tester.tap(find.text('Feed root'));
    await tester.pumpAndSettle();
    await _report(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Feed'));
    await tester.pumpAndSettle();
    expect(find.text('Feed root'), findsOneWidget);
    expect(find.text('Reported post detail'), findsNothing);
    expect(router.routerDelegate.currentConfiguration.uri.path, '/feed');
    // The reported content is not left underneath the Feed.
    expect(router.canPop(), isFalse);
    expect(_reportPosts(client), 1);
  });

  testWidgets(
      'repeated report: Feed still opens the Feed root, one request '
      'per submission', (tester) async {
    final (client, _) = await _mount(tester, initialLocation: '/feed');
    for (var round = 1; round <= 2; round++) {
      await tester.tap(find.text('Feed root'));
      await tester.pumpAndSettle();
      await _report(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Feed'));
      await tester.pumpAndSettle();
      expect(find.text('Feed root'), findsOneWidget);
      expect(find.text('Reported post detail'), findsNothing);
      expect(_reportPosts(client), round);
    }
  });

  testWidgets('report on a directly opened publication: Feed opens the Feed',
      (tester) async {
    final (client, router) =
        await _mount(tester, initialLocation: '/posts/$_postId');
    await _report(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Feed'));
    await tester.pumpAndSettle();
    expect(find.text('Feed root'), findsOneWidget);
    expect(router.canPop(), isFalse);
    expect(_reportPosts(client), 1);
  });

  testWidgets(
      'Android Back from the confirmation returns to the content '
      'without resubmitting', (tester) async {
    final (client, _) = await _mount(tester, initialLocation: '/feed');
    await tester.tap(find.text('Feed root'));
    await tester.pumpAndSettle();
    await _report(tester);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Reported post detail'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Feed root'), findsOneWidget);
    expect(_reportPosts(client), 1);
  });
}
