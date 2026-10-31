import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/core/lifecycle/app_resume.dart';
import 'package:mushukistan_frontend/core/network/api_error.dart';
import 'package:mushukistan_frontend/features/notifications/data/notification_api.dart';
import 'package:mushukistan_frontend/features/notifications/presentation/notification_center_screen.dart';

import 'support/fakes.dart';

/// Inbox server. Each list answer reflects the state at the moment it was requested; a held
/// request ([holdNext]) answers later, like a slow network.
class _Inbox {
  bool allRead = false;
  bool offline = false;
  Completer<void>? holdNext;

  void install(FakeApiClient client) {
    client
      ..setHandler('GET', 'notifications', (_) async {
        final readAtRequest = allRead;
        final hold = holdNext;
        holdNext = null;
        if (hold != null) await hold.future;
        if (offline) {
          throw const MushukistanApiException(
            kind: ApiFailureKind.network,
            code: 'NETWORK_ERROR',
            message: 'offline',
          );
        }
        return {
          'items': [
            {
              'id': '11111111-1111-1111-1111-111111111111',
              'kind': 'comment',
              'actor_name': 'Aziz',
              'target_kind': 'lost_pet',
              'target_id': '22222222-2222-2222-2222-222222222222',
              'created_at': '2026-10-07T12:00:00Z',
              'read_at': readAtRequest ? '2026-10-07T13:00:00Z' : null,
            },
          ],
          'next_cursor': null,
          'limit': 20,
        };
      })
      ..setHandler('GET', 'notifications/unread-count',
          (_) => {'count': allRead ? 0 : 1})
      ..setHandler('POST', 'notifications/read-all', (_) {
        allRead = true;
        return null;
      });
  }
}

Future<(FakeApiClient, void Function(Duration))> _pump(
    WidgetTester tester, _Inbox inbox) async {
  final client = FakeApiClient();
  inbox.install(client);
  var now = const Duration(hours: 1);
  final container = ProviderContainer(overrides: [
    notificationApiProvider.overrideWithValue(NotificationApi(client)),
    monotonicClockProvider.overrideWithValue(() => now),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: NotificationCenterScreen()),
  ));
  await tester.pumpAndSettle();
  void awayFor(Duration duration) {
    final tracker = container.read(appResumeProvider.notifier);
    tracker.handleLifecycle(AppLifecycleState.paused);
    now += duration;
    tracker.handleLifecycle(AppLifecycleState.resumed);
  }

  return (client, awayFor);
}

int _listRequests(FakeApiClient client) =>
    client.calls.where((c) => c.path == 'notifications').length;

final _markAll = find.text('Mark all as read');

void main() {
  testWidgets('a reload that answers late cannot undo "Mark all as read"',
      (tester) async {
    final inbox = _Inbox();
    final (client, awayFor) = await _pump(tester, inbox);
    expect(_markAll, findsOneWidget);

    // Back after a while: a reload starts, and the network is slow.
    final slow = inbox.holdNext = Completer<void>();
    awayFor(const Duration(minutes: 10));
    await tester.pump();
    final requests = _listRequests(client);

    // Meanwhile the user marks everything read; their own reload runs at once.
    await tester.tap(_markAll);
    await tester.pumpAndSettle();
    expect(_listRequests(client), requests + 1);
    expect(_markAll, findsNothing);

    // The older answer (still unread) arrives last and must be dropped.
    slow.complete();
    await tester.pumpAndSettle();
    expect(_markAll, findsNothing);
  });

  testWidgets('back after 5 minutes: the inbox reloads; offline keeps it',
      (tester) async {
    final inbox = _Inbox();
    final (client, awayFor) = await _pump(tester, inbox);
    final requests = _listRequests(client);

    awayFor(const Duration(minutes: 2));
    await tester.pumpAndSettle();
    expect(_listRequests(client), requests);

    inbox.allRead = true;
    awayFor(const Duration(minutes: 6));
    await tester.pumpAndSettle();
    expect(_listRequests(client), requests + 1);
    expect(_markAll, findsNothing);

    inbox
      ..allRead = false
      ..offline = true;
    awayFor(const Duration(minutes: 6));
    await tester.pumpAndSettle();
    expect(find.text('Aziz commented on your post'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });
}
