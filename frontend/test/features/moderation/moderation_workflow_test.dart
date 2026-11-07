import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mushukistan_frontend/core/localization/app_strings.dart';
import 'package:mushukistan_frontend/core/localization/l10n.dart';
import 'package:mushukistan_frontend/core/localization/language_controller.dart';
import 'package:mushukistan_frontend/core/network/api_client.dart';
import 'package:mushukistan_frontend/core/network/api_error.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';
import 'package:mushukistan_frontend/features/moderation/presentation/moderation_labels.dart';
import 'package:mushukistan_frontend/features/moderation/presentation/screens/moderation_report_detail_screen.dart';
import 'package:mushukistan_frontend/features/moderation/presentation/screens/moderation_reports_screen.dart';

import '../../support/fakes.dart';

Map<String, Object?> _report(
  String id, {
  String status = 'open',
  String targetType = 'post',
  String reason = 'Spam link',
  Map<String, Object?>? target = const {},
  String? reporter = 'B1 Alice',
  String createdAt = '2026-11-05T10:15:00Z',
  String? handledBy,
  String? handledAt,
}) {
  return {
    'id': id,
    'reporter':
        reporter == null ? null : {'id': 'u-$reporter', 'name': reporter},
    'target_type': targetType,
    'target_id': 'target-$id',
    if (target != null)
      'target': {
        'id': 'target-$id',
        'target_type': targetType,
        'title': 'Reported text of $id',
        'is_public': true,
        'is_active': true,
        ...target,
      },
    'reason': reason,
    'status': status,
    if (handledBy != null) 'handled_by': {'id': 'm-1', 'name': handledBy},
    if (handledAt != null) 'handled_at': handledAt,
    'created_at': createdAt,
  };
}

Map<String, Object?> _page(List<Map<String, Object?>> items, {String? next}) =>
    {'items': items, 'limit': 20, 'next_cursor': next};

const _conflict = MushukistanApiException(
  kind: ApiFailureKind.conflict,
  code: 'REPORT_ALREADY_HANDLED',
  message: 'Report has already been handled.',
  statusCode: 409,
);

const _network = MushukistanApiException(
  kind: ApiFailureKind.network,
  code: 'NETWORK_ERROR',
  message: 'offline',
);

Future<(FakeApiClient, ProviderContainer)> _pump(
  WidgetTester tester, {
  required FakeApiClient client,
  String initialLocation = '/moderation/reports',
  AppLanguage language = AppLanguage.english,
}) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(overrides: [
    apiClientProvider.overrideWithValue(client),
  ]);
  container.read(appLanguageProvider.notifier).state = language;
  addTearDown(container.dispose);
  final router = GoRouter(initialLocation: initialLocation, routes: [
    GoRoute(
      path: '/moderation/reports',
      builder: (_, __) => const ModerationReportsScreen(),
    ),
    GoRoute(
      path: '/moderation/reports/:id',
      builder: (_, state) =>
          ModerationReportDetailScreen(reportId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/posts/:id',
      builder: (_, state) =>
          Scaffold(body: Text('post route ${state.pathParameters['id']}')),
    ),
    GoRoute(
      path: '/moderation/posts/:id/history',
      builder: (_, state) =>
          Scaffold(body: Text('history route ${state.pathParameters['id']}')),
    ),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: Consumer(
      builder: (context, ref, _) => MaterialApp.router(
        locale: ref.watch(appLanguageProvider).locale,
        supportedLocales: L10n.supportedLocales,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        routerConfig: router,
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return (client, container);
}

List<ApiCall> _patches(FakeApiClient client) =>
    client.calls.where((call) => call.method == 'PATCH').toList();

void main() {
  group('labels', () {
    final strings = AppStrings.forLanguage(AppLanguage.english);
    ReportData data(Map<String, Object?> json) => ReportData.fromJson(json);

    test('unknown enum values fall back without exposing raw codes', () {
      expect(reportStatusLabel(strings, 'escalated'), 'Unknown status');
      expect(reportTargetTypeLabel(strings, 'future_thing'), 'Other content');
    });

    test('target state distinguishes deleted, suspended and missing', () {
      expect(reportTargetState(data(_report('a'))), ReportTargetState.visible);
      expect(
          reportTargetState(data(_report('b', target: {'is_public': false}))),
          ReportTargetState.private);
      expect(
          reportTargetState(data(_report('c', target: {
            'is_active': false,
            'deleted_at': '2026-11-05T11:00:00Z',
          }))),
          ReportTargetState.deleted);
      expect(
          reportTargetState(data(
              _report('d', targetType: 'user', target: {'is_active': false}))),
          ReportTargetState.suspended);
      expect(reportTargetState(data(_report('e', target: null))),
          ReportTargetState.unavailable);
    });

    test('removal is only offered for content that still exists', () {
      expect(removalFor(data(_report('a')))?.action, 'soft_delete_post');
      expect(removalFor(data(_report('b', targetType: 'lost_pet')))?.action,
          'soft_delete_post');
      expect(removalFor(data(_report('c', targetType: 'comment')))?.action,
          'soft_delete_comment');
      expect(removalFor(data(_report('d', targetType: 'user')))?.isSuspension,
          isTrue);
      expect(removalFor(data(_report('e', targetType: 'cat'))), isNull);
      expect(
          removalFor(data(_report('f', target: {'is_active': false}))), isNull);
      expect(removalFor(data(_report('g', target: null))), isNull);
    });
  });

  testWidgets('queue shows reporter, time, type and target state badges',
      (tester) async {
    final client = FakeApiClient()
      ..setHandler(
          'GET',
          'moderation/reports',
          (_) => _page([
                _report('r1'),
                _report('r2', targetType: 'comment', target: {
                  'is_active': false,
                  'deleted_at': '2026-11-05T11:00:00Z',
                }),
                _report('r3',
                    targetType: 'lost_pet', target: null, reporter: null),
              ]));
    await _pump(tester, client: client);

    expect(find.text('Post'), findsOneWidget);
    expect(find.text('Comment'), findsOneWidget);
    expect(find.text('Lost pet post'), findsOneWidget);
    expect(find.text('Deleted'), findsOneWidget);
    expect(find.text('Unavailable'), findsOneWidget);
    expect(find.textContaining('B1 Alice · Nov 5, 2026'), findsNWidgets(2));
    expect(find.textContaining('Deleted account · '), findsOneWidget);
    expect(find.text('post'), findsNothing);
    expect(find.text('No more reports.'), findsOneWidget);
    expect(client.calls.single.queryParameters?['status'], 'open');
  });

  testWidgets('status filters load resolved and dismissed history',
      (tester) async {
    final client = FakeApiClient()
      ..setHandler('GET', 'moderation/reports', (call) {
        return switch (call.queryParameters?['status']) {
          'resolved' => _page([
              _report('done',
                  status: 'resolved',
                  handledBy: 'B1 Moderator',
                  handledAt: '2026-11-05T12:00:00Z',
                  target: {'is_active': false})
            ]),
          'dismissed' => _page([]),
          _ => _page([]),
        };
      });
    await _pump(tester, client: client);
    expect(find.text('No open reports.'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Resolved'));
    await tester.pumpAndSettle();
    expect(find.text('Resolved'), findsNWidgets(2)); // chip + status badge
    expect(find.textContaining('Handled by B1 Moderator'), findsOneWidget);
    expect(find.text('Deleted'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Dismissed'));
    await tester.pumpAndSettle();
    expect(find.text('No dismissed reports.'), findsOneWidget);

    expect(client.calls.map((call) => call.queryParameters?['status']).toList(),
        ['open', 'resolved', 'dismissed']);
  });

  testWidgets('queue paginates without duplicates', (tester) async {
    final client = FakeApiClient()
      ..setHandler('GET', 'moderation/reports', (call) {
        if (call.queryParameters?['cursor'] == null) {
          return _page([_report('p1'), _report('p2')], next: 'c1');
        }
        // A report that moved between pages must not be listed twice.
        return _page([_report('p2'), _report('p3')]);
      });
    await _pump(tester, client: client);

    await tester.tap(find.text('Load more reports'));
    await tester.pumpAndSettle();

    expect(find.byType(ModerationReportCard), findsNWidgets(3));
    expect(find.text('No more reports.'), findsOneWidget);
  });

  testWidgets('queue load errors distinguish network from missing access',
      (tester) async {
    var fail = _network as Object;
    final client = FakeApiClient()
      ..setHandler('GET', 'moderation/reports', (_) => throw fail);
    final (_, container) = await _pump(tester, client: client);
    expect(find.text('Could not load reports. Check your connection.'),
        findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    fail = const MushukistanApiException(
        kind: ApiFailureKind.forbidden, code: 'FORBIDDEN', message: 'no');
    container.invalidate(moderationReportsProvider);
    await tester.pumpAndSettle();
    expect(find.text('Moderator access is required.'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('detail shows full report metadata and content state',
      (tester) async {
    final client = FakeApiClient()
      ..setHandler('GET', 'moderation/reports/r1', (_) => _report('r1'));
    await _pump(tester,
        client: client, initialLocation: '/moderation/reports/r1');

    expect(find.text('Reason'), findsOneWidget);
    expect(find.text('Spam link'), findsOneWidget);
    expect(find.text('Reported by'), findsOneWidget);
    expect(find.text('B1 Alice'), findsOneWidget);
    expect(find.text('Submitted'), findsOneWidget);
    expect(find.textContaining('Nov 5, 2026'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Visible'), findsOneWidget);
    expect(find.text('Reported text of r1'), findsOneWidget);

    await tester.tap(find.text('Open content'));
    await tester.pumpAndSettle();
    expect(find.text('post route target-r1'), findsOneWidget);
  });

  testWidgets(
      'already-deleted target: state and time shown, content hidden, '
      'no removal offered, non-destructive handling still possible',
      (tester) async {
    final client = FakeApiClient()
      ..setHandler(
          'GET',
          'moderation/reports/r2',
          (_) => _report('r2', targetType: 'comment', target: {
                'is_active': false,
                'deleted_at': '2026-11-05T11:00:00Z',
              }))
      ..setHandler('PATCH', 'moderation/reports/r2',
          (_) => _report('r2', status: 'resolved', targetType: 'comment'));
    await _pump(tester,
        client: client, initialLocation: '/moderation/reports/r2');

    expect(find.text('Deleted'), findsOneWidget);
    expect(find.textContaining('Deleted Nov 5, 2026'), findsOneWidget);
    expect(find.text('Reported text of r2'), findsNothing);
    expect(find.text('Resolve and remove'), findsNothing);
    expect(find.textContaining('cannot be removed again'), findsOneWidget);
    expect(find.text('Open content'), findsNothing);

    await tester.tap(find.text('Resolve, keep content'));
    await tester.pump();
    await tester.tap(find.text('Save moderation decision'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(_patches(client).single.body,
        {'status': 'resolved'}); // no removal action
  });

  testWidgets('removal asks for confirmation; Cancel submits nothing',
      (tester) async {
    final client = FakeApiClient()
      ..setHandler('GET', 'moderation/reports/r1', (_) => _report('r1'))
      ..setHandler('PATCH', 'moderation/reports/r1',
          (_) => _report('r1', status: 'resolved'));
    await _pump(tester,
        client: client, initialLocation: '/moderation/reports/r1');

    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Save moderation decision'))
            .onPressed,
        isNull,
        reason: 'nothing is preselected');
    await tester.tap(find.text('Resolve and remove'));
    await tester.pump();
    await tester.tap(find.text('Save moderation decision'));
    await tester.pumpAndSettle();

    expect(find.text('Remove this post?'), findsOneWidget);
    expect(find.textContaining('“Reported text of r1” will be removed'),
        findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(_patches(client), isEmpty);
    expect(find.text('Resolve and remove'), findsOneWidget);
  });

  testWidgets('confirmed removal submits exactly one decision', (tester) async {
    final gate = Completer<void>();
    final client = FakeApiClient()
      ..setHandler('GET', 'moderation/reports/r1', (_) => _report('r1'))
      ..setHandler('GET', 'moderation/reports', (_) => _page([]))
      ..setHandler('PATCH', 'moderation/reports/r1', (_) async {
        await gate.future;
        return _report('r1', status: 'resolved', target: {'is_active': false});
      });
    await _pump(tester,
        client: client, initialLocation: '/moderation/reports/r1');

    await tester.tap(find.text('Resolve and remove'));
    await tester.pump();
    await tester.tap(find.text('Save moderation decision'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pump();

    // While the request is pending, the Save button is disabled and further
    // taps cannot open the dialog or submit again.
    await tester.pump(const Duration(milliseconds: 500));
    final save = find.byType(FilledButton);
    expect(save, findsOneWidget);
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.tap(save, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(AlertDialog), findsNothing);
    expect(_patches(client), hasLength(1));
    gate.complete();
    await tester.pumpAndSettle();

    final patch = _patches(client).single;
    expect(patch.body, {'status': 'resolved', 'action': 'soft_delete_post'});
    expect(find.text('Decision saved.'), findsOneWidget);
  });

  testWidgets('dismiss needs no confirmation', (tester) async {
    final client = FakeApiClient()
      ..setHandler('GET', 'moderation/reports/r1', (_) => _report('r1'))
      ..setHandler('PATCH', 'moderation/reports/r1',
          (_) => _report('r1', status: 'dismissed'));
    await _pump(tester,
        client: client, initialLocation: '/moderation/reports/r1');

    await tester.tap(find.text('Dismiss report'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Not spam');
    await tester.tap(find.text('Save moderation decision'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(_patches(client).single.body,
        {'status': 'dismissed', 'note': 'Not spam'});
  });

  testWidgets('suspension asks for its own confirmation', (tester) async {
    final client = FakeApiClient()
      ..setHandler(
          'GET',
          'moderation/reports/u1',
          (_) =>
              _report('u1', targetType: 'user', target: {'title': 'B1 Carol'}));
    await _pump(tester,
        client: client, initialLocation: '/moderation/reports/u1');

    await tester.tap(find.text('Resolve and suspend account'));
    await tester.pump();
    await tester.tap(find.text('Save moderation decision'));
    await tester.pumpAndSettle();

    expect(find.text('Suspend this account?'), findsOneWidget);
    expect(
        find.textContaining('B1 Carol will no longer be able'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(_patches(client), isEmpty);
  });

  testWidgets(
      'conflict refreshes the report, explains it and removes the stale form',
      (tester) async {
    var handled = false;
    final client = FakeApiClient()
      ..setHandler(
          'GET',
          'moderation/reports/r1',
          (_) => handled
              ? _report('r1',
                  status: 'dismissed',
                  handledBy: 'B1 Other Moderator',
                  handledAt: '2026-11-05T12:00:00Z')
              : _report('r1'))
      ..setHandler('GET', 'moderation/reports', (_) => _page([]))
      ..setHandler('PATCH', 'moderation/reports/r1', (_) {
        handled = true;
        throw _conflict;
      });
    await _pump(tester,
        client: client, initialLocation: '/moderation/reports/r1');

    await tester.tap(find.text('Resolve, keep content'));
    await tester.pump();
    await tester.tap(find.text('Save moderation decision'));
    await tester.pumpAndSettle();

    expect(find.text('Already handled'), findsOneWidget);
    expect(find.textContaining('Another moderator handled this report'),
        findsOneWidget);
    expect(find.text('Could not load reports.'), findsNothing);
    expect(find.text('Dismissed'), findsOneWidget);
    expect(find.text('B1 Other Moderator'), findsOneWidget);
    expect(find.text('Save moderation decision'), findsNothing);
    expect(find.text('This report is closed. Its decision cannot be changed.'),
        findsOneWidget);
    expect(_patches(client), hasLength(1));
    expect(
        client.calls
            .where(
                (c) => c.method == 'GET' && c.path == 'moderation/reports/r1')
            .length,
        2,
        reason: 'the authoritative report was fetched again');
  });

  testWidgets('a network failure keeps the decision for retry', (tester) async {
    var attempts = 0;
    final client = FakeApiClient()
      ..setHandler('GET', 'moderation/reports/r1', (_) => _report('r1'))
      ..setHandler('GET', 'moderation/reports', (_) => _page([]))
      ..setHandler('PATCH', 'moderation/reports/r1', (_) {
        attempts++;
        if (attempts == 1) throw _network;
        return _report('r1', status: 'dismissed');
      });
    await _pump(tester,
        client: client, initialLocation: '/moderation/reports/r1');

    await tester.tap(find.text('Dismiss report'));
    await tester.pump();
    await tester.tap(find.text('Save moderation decision'));
    await tester.pumpAndSettle();
    expect(
        find.text(
            'Could not save the decision. Check your connection and try again.'),
        findsOneWidget);
    expect(find.text('Could not load reports.'), findsNothing);

    await tester.tap(find.text('Save moderation decision'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.text('Decision saved.'), findsOneWidget);
  });

  testWidgets('missing report shows an unavailable state', (tester) async {
    final client = FakeApiClient()
      ..setHandler(
          'GET',
          'moderation/reports/gone',
          (_) => throw const MushukistanApiException(
              kind: ApiFailureKind.notFound,
              code: 'REPORT_NOT_FOUND',
              message: 'Report not found.'));
    await _pump(tester,
        client: client, initialLocation: '/moderation/reports/gone');

    expect(find.text('This report is no longer available.'), findsOneWidget);
    expect(find.text('Back to reports'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('processed report is read-only', (tester) async {
    final client = FakeApiClient()
      ..setHandler(
          'GET',
          'moderation/reports/done',
          (_) => _report('done',
                  status: 'resolved',
                  handledBy: 'B1 Moderator',
                  handledAt: '2026-11-05T12:00:00Z',
                  target: {
                    'is_active': false,
                    'deleted_at': '2026-11-05T12:00:00Z'
                  }));
    await _pump(tester,
        client: client, initialLocation: '/moderation/reports/done');

    expect(find.text('Resolved'), findsOneWidget);
    expect(find.text('Handled by'), findsOneWidget);
    expect(find.text('B1 Moderator'), findsOneWidget);
    expect(find.text('Save moderation decision'), findsNothing);
    expect(find.text('Dismiss report'), findsNothing);
    await tester.tap(find.text('View post history'));
    await tester.pumpAndSettle();
    expect(find.text('history route target-done'), findsOneWidget);
  });

  for (final (language, open, post, visible, raw) in [
    (AppLanguage.russian, 'Открыта', 'Публикация', 'Виден', 'post'),
    (AppLanguage.uzbek, 'Ochiq', 'Post', 'Koʻrinadi', 'unknown'),
  ]) {
    testWidgets('${language.name}: moderation values are localized',
        (tester) async {
      final client = FakeApiClient()
        ..setHandler(
            'GET',
            'moderation/reports/r1',
            (_) => _report('r1',
                target: {'status': 'unknown', 'title': 'User text stays'}));
      final (_, container) = await _pump(tester,
          client: client,
          initialLocation: '/moderation/reports/r1',
          language: language);

      expect(find.text(open), findsOneWidget);
      expect(find.text(post), findsOneWidget);
      expect(find.text(visible), findsOneWidget);
      expect(find.text('User text stays'), findsOneWidget);
      for (final code in ['post', 'open', 'resolved', 'unknown', raw]) {
        expect(find.text(code), findsNothing, reason: code);
        expect(find.textContaining('| $code'), findsNothing);
      }

      // Selecting a decision and switching language keeps the report state.
      final strings = AppStrings.forLanguage(language);
      await tester.tap(find.text(strings.decisionDismiss));
      await tester.pump();
      container.read(appLanguageProvider.notifier).state = AppLanguage.english;
      await tester.pumpAndSettle();
      expect(find.text('Open'), findsOneWidget);
      final save = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Save moderation decision'));
      expect(save.onPressed, isNotNull, reason: 'decision kept');
    });
  }
}
