import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/core/localization/language_controller.dart';
import 'package:mushukistan_frontend/core/network/api_client.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';
import 'package:mushukistan_frontend/features/comments/presentation/screens/comments_screen.dart';
import 'package:mushukistan_frontend/features/notifications/data/notification_api.dart';
import 'package:mushukistan_frontend/features/notifications/presentation/notification_center_screen.dart';
import 'package:mushukistan_frontend/features/notifications/presentation/notification_strings.dart';

class _NotificationClient extends Fake implements MushukistanApiClient {
  bool markedAll = false;
  bool markedOne = false;

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    required T Function(Object? json) decoder,
    bool authenticated = true,
  }) async {
    if (path == 'notifications') {
      return decoder({
        'items': [
          {
            'id': '11111111-1111-1111-1111-111111111111',
            'kind': 'comment',
            'actor_name': 'Aziz',
            'target_kind': 'lost_pet',
            'target_id': '22222222-2222-2222-2222-222222222222',
            'comment_id': '33333333-3333-3333-3333-333333333333',
            'created_at': '2026-10-07T12:00:00Z',
            'read_at': markedAll || markedOne ? '2026-10-07T13:00:00Z' : null,
          },
        ],
        'next_cursor': null,
        'limit': 20,
      });
    }
    if (path == 'notifications/unread-count') {
      return decoder({'count': markedAll || markedOne ? 0 : 1});
    }
    throw StateError('Unexpected GET $path');
  }

  @override
  Future<T> postJson<T>(
    String path, {
    Object? body,
    Map<String, dynamic>? queryParameters,
    required T Function(Object? json) decoder,
    bool authenticated = true,
    String? bearerToken,
  }) async {
    if (path == 'notifications/read-all') markedAll = true;
    if (path.endsWith('/read')) markedOne = true;
    return decoder(null);
  }
}

void main() {
  test('notification targets use only internal allowlisted routes', () {
    const id = '22222222-2222-2222-2222-222222222222';
    expect(notificationTargetPath('lost_pet', id), '/lost-pets/$id');
    expect(notificationTargetPath('post', id), '/posts/$id');
    expect(notificationTargetPath('adoption_post', id), '/adoption-posts/$id');
    expect(notificationTargetPath('https://example.com', id), isNull);
    expect(notificationTargetPath('lost_pet', '../../settings'), isNull);
  });

  test('notification copy is available in all supported languages', () {
    for (final language in AppLanguage.values) {
      final copy = NotificationStrings(language.code);
      expect(copy.get('title'), isNotEmpty);
      expect(copy.get('comment'), isNotEmpty);
      expect(copy.get('nearby_hint'), contains('500'));
    }
  });

  testWidgets('bell hides zero and bounds large unread counts', (tester) async {
    Future<void> showCount(int count) async {
      await tester.pumpWidget(ProviderScope(
        key: ValueKey(count),
        overrides: [
          unreadNotificationCountProvider.overrideWith((ref) async => count),
        ],
        child: const MaterialApp(
          home: Scaffold(body: NotificationBell()),
        ),
      ));
      await tester.pumpAndSettle();
    }

    await showCount(0);
    expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isFalse);
    await showCount(120);
    expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isTrue);
    expect(find.text('99+'), findsOneWidget);
  });

  testWidgets('inbox stays unread until explicitly marked, then refreshes',
      (tester) async {
    final client = _NotificationClient();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        notificationApiProvider.overrideWithValue(NotificationApi(client)),
      ],
      child: const MaterialApp(home: NotificationCenterScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Aziz commented on your post'), findsOneWidget);
    expect(client.markedAll, isFalse);
    await tester.tap(find.text('Mark all as read'));
    await tester.pumpAndSettle();
    expect(client.markedAll, isTrue);
    expect(find.text('Aziz commented on your post'), findsOneWidget);
  });

  testWidgets(
      'opening one unavailable item marks it read and explains the target',
      (tester) async {
    final client = _NotificationClient();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        notificationApiProvider.overrideWithValue(NotificationApi(client)),
        mushukistanApiProvider
            .overrideWithValue(MushukistanApi(client: client)),
      ],
      child: const MaterialApp(home: NotificationCenterScreen()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aziz commented on your post'));
    await tester.pumpAndSettle();
    expect(client.markedOne, isTrue);
    expect(client.markedAll, isFalse);
    expect(find.text('This content is no longer available.'), findsOneWidget);
  });

  testWidgets('notification comment link scrolls to existing comments section',
      (tester) async {
    final controller = ScrollController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          controller: controller,
          child: const Column(children: [
            SizedBox(height: 1000),
            CommentDeepLinkFocus(focus: true, child: Text('Comments section')),
            SizedBox(height: 300),
          ]),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(0));
  });
}
