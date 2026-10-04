import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';
import 'package:mushukistan_frontend/features/auth/application/auth_controller.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_models.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_repository.dart';
import 'package:mushukistan_frontend/features/feed/presentation/screens/feed_screen.dart';
import 'package:mushukistan_frontend/features/lost_pets/presentation/screens/lost_pet_detail_screen.dart';
import 'package:mushukistan_frontend/features/lost_pets/presentation/screens/lost_pet_edit_screen.dart';
import 'package:mushukistan_frontend/features/lost_pets/presentation/screens/my_lost_pets_screen.dart';

import '../../support/fakes.dart';

ProviderContainer _container(
  FakeApiClient apiClient, {
  String? userId = '11111111-1111-4111-8111-111111111111',
}) =>
    ProviderContainer(overrides: [
      mushukistanApiProvider
          .overrideWithValue(MushukistanApi(client: apiClient)),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(
        restoreResult: userId == null
            ? const SessionRestoreMissing()
            : SessionRestoreSuccess(
                AuthSession.restored(
                  accessToken: 'token',
                  user: testUser(id: userId),
                ),
              ),
      )),
      googleIdentityTokenProvider
          .overrideWithValue(FakeGoogleIdentityTokenProvider()),
    ]);

Map<String, Object?> _pet({required bool resolved}) => {
      'id': 'pet-1',
      'pet_name': 'Mittens',
      'author': {'id': 'owner-1', 'name': 'Owner'},
      'owner_phone_number': '+998 90 123 45 67',
      'owner_telegram_username': 'mittens_owner',
      'photo_url': 'https://example.com/pet.jpg',
      'photo_urls': ['https://example.com/pet.jpg'],
      'last_seen_location': {'latitude': 41.3, 'longitude': 69.25},
      'created_at': '2026-09-28T09:00:00Z',
      'is_resolved': resolved,
      'comment_count': 0,
      'additional_info': 'Near the park',
    };

void main() {
  testWidgets('only the owner sees Lost Pet edit and delete controls',
      (tester) async {
    final apiClient = FakeApiClient();
    apiClient.setHandler('GET', 'lost-pets/pet-1', (_) => _pet(resolved: true));
    apiClient.setHandler('GET', 'lost-pets/pet-1/comments',
        (_) => {'items': <Object>[], 'next_cursor': null, 'limit': 20});

    final ownerContainer = _container(apiClient, userId: 'owner-1');
    addTearDown(ownerContainer.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: ownerContainer,
      child: const MaterialApp(home: LostPetDetailScreen(lostPetId: 'pet-1')),
    ));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Edit lost pet'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Edit lost pet'), findsOneWidget);
    expect(find.text('Delete lost pet'), findsOneWidget);
    await tester.tap(find.text('Delete lost pet'));
    await tester.pumpAndSettle();
    expect(find.text('This lost pet post will be removed.'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('another user does not see Lost Pet edit or delete controls',
      (tester) async {
    final apiClient = FakeApiClient();
    apiClient.setHandler(
        'GET', 'lost-pets/pet-1', (_) => _pet(resolved: false));
    apiClient.setHandler('GET', 'lost-pets/pet-1/comments',
        (_) => {'items': <Object>[], 'next_cursor': null, 'limit': 20});
    final container = _container(apiClient, userId: 'other-1');
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: LostPetDetailScreen(lostPetId: 'pet-1')),
    ));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(find.text('Edit lost pet'), findsNothing);
    expect(find.text('Delete lost pet'), findsNothing);
  });

  testWidgets('guest does not see Lost Pet edit or delete controls',
      (tester) async {
    final apiClient = FakeApiClient();
    apiClient.setHandler(
        'GET', 'lost-pets/pet-1', (_) => _pet(resolved: false));
    apiClient.setHandler('GET', 'lost-pets/pet-1/comments',
        (_) => {'items': <Object>[], 'next_cursor': null, 'limit': 20});
    final container = _container(apiClient, userId: null);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: LostPetDetailScreen(lostPetId: 'pet-1')),
    ));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(find.text('Edit lost pet'), findsNothing);
    expect(find.text('Delete lost pet'), findsNothing);
  });

  testWidgets('Lost Pet detail uses a readable column and Report overflow',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final apiClient = FakeApiClient();
    apiClient.setHandler('GET', 'lost-pets/pet-1', (_) => _pet(resolved: true));
    apiClient.setHandler('GET', 'lost-pets/pet-1/comments',
        (_) => {'items': <Object>[], 'next_cursor': null, 'limit': 20});
    final container = _container(apiClient, userId: 'owner-1');
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: LostPetDetailScreen(lostPetId: 'pet-1')),
    ));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(ListView).first).width, 760);
    expect(find.widgetWithText(OutlinedButton, 'Report'), findsNothing);
    expect(
        find.widgetWithText(FilledButton, 'Delete lost pet'), findsOneWidget);
    await tester.tap(find.byTooltip('Post actions'));
    await tester.pumpAndSettle();
    expect(find.text('Report'), findsOneWidget);
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(800, 900);
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(ListView).first).width, 760);

    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(ListView).first).width, 390);
    expect(tester.takeException(), isNull);
  });

  testWidgets('non-owner Report menu keeps the Lost Pet target id',
      (tester) async {
    final apiClient = FakeApiClient();
    apiClient.setHandler(
        'GET', 'lost-pets/pet-1', (_) => _pet(resolved: false));
    apiClient.setHandler('GET', 'lost-pets/pet-1/comments',
        (_) => {'items': <Object>[], 'next_cursor': null, 'limit': 20});
    final container = _container(apiClient, userId: 'another-user');
    addTearDown(container.dispose);
    final router = GoRouter(initialLocation: '/lost-pets/pet-1', routes: [
      GoRoute(
        path: '/lost-pets/:lostPetId',
        builder: (_, state) => LostPetDetailScreen(
          lostPetId: state.pathParameters['lostPetId']!,
        ),
      ),
      GoRoute(
        path: '/report',
        builder: (_, state) => Scaffold(
          body: Text(
            'Report ${state.uri.queryParameters['type']} '
            '${state.uri.queryParameters['id']}',
          ),
        ),
      ),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Edit lost pet'), findsNothing);
    await tester.tap(find.byTooltip('Post actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();
    expect(find.text('Report lost_pet pet-1'), findsOneWidget);
  });

  testWidgets('successful Lost Pet deletion confirms on the destination',
      (tester) async {
    final apiClient = FakeApiClient();
    apiClient.setHandler('GET', 'lost-pets/pet-1', (_) => _pet(resolved: true));
    apiClient.setHandler('GET', 'lost-pets/pet-1/comments',
        (_) => {'items': <Object>[], 'next_cursor': null, 'limit': 20});
    apiClient.setHandler('DELETE', 'lost-pets/pet-1', (_) => null);
    final container = _container(apiClient, userId: 'owner-1');
    addTearDown(container.dispose);
    final router = GoRouter(initialLocation: '/destination', routes: [
      GoRoute(
        path: '/destination',
        builder: (context, _) => Scaffold(
          body: TextButton(
            onPressed: () => context.push('/lost-pets/pet-1'),
            child: const Text('Destination'),
          ),
        ),
      ),
      GoRoute(
        path: '/lost-pets/:lostPetId',
        builder: (_, state) => LostPetDetailScreen(
          lostPetId: state.pathParameters['lostPetId']!,
        ),
      ),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Destination'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Delete lost pet'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Delete lost pet'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete', skipOffstage: false).last);
    await tester.pumpAndSettle();

    expect(find.text('Destination'), findsOneWidget);
    expect(find.text('Post deleted'), findsOneWidget);
    expect(
        apiClient.calls.where((call) => call.method == 'DELETE'), hasLength(1));
  });

  testWidgets('Lost Pet edit screen loads existing mutable values',
      (tester) async {
    final apiClient = FakeApiClient();
    apiClient.setHandler('GET', 'lost-pets/pet-1', (_) => _pet(resolved: true));
    final container = _container(apiClient, userId: 'owner-1');
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: LostPetEditScreen(lostPetId: 'pet-1')),
    ));
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate((widget) =>
          widget is TextFormField && widget.controller?.text == 'Mittens'),
      findsOneWidget,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -800));
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate((widget) =>
          widget is TextFormField &&
          widget.controller?.text == '+998 90 123 45 67'),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate((widget) =>
          widget is TextFormField &&
          widget.controller?.text == 'mittens_owner'),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate((widget) =>
          widget is TextFormField &&
          widget.controller?.text == 'Near the park'),
      findsOneWidget,
    );
  });

  testWidgets(
      'Feed applies successful Lost Pet edits and deletes if refresh fails',
      (tester) async {
    final apiClient = FakeApiClient();
    var failRefresh = false;
    apiClient.setHandler('GET', 'lost-pets', (_) {
      if (failRefresh) throw StateError('Feed refresh unavailable');
      return {
        'items': [_pet(resolved: false)],
        'next_cursor': null,
        'limit': 30,
      };
    });
    final container = _container(apiClient);
    addTearDown(container.dispose);
    container.read(feedModeProvider.notifier).state = 'lost_pets';

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: FeedScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Mittens', findRichText: true), findsOneWidget);

    final updated = LostPetData.fromJson({
      ..._pet(resolved: false),
      'pet_name': 'Updated Mittens',
    });
    container.read(lostPetMutationOverridesProvider.notifier).state = {
      'pet-1': updated,
    };
    failRefresh = true;
    container.read(postMutationRevisionProvider.notifier).state++;
    await tester.pump();
    expect(find.textContaining('Updated Mittens', findRichText: true),
        findsOneWidget);
    expect(
      find.textContaining('Cat name: Mittens', findRichText: true),
      findsNothing,
    );

    container.read(deletedLostPetIdsProvider.notifier).state = {'pet-1'};
    container.read(postMutationRevisionProvider.notifier).state++;
    await tester.pump();
    expect(find.textContaining('Updated Mittens', findRichText: true),
        findsNothing);
    await tester.pumpAndSettle();
    expect(find.textContaining('Updated Mittens', findRichText: true),
        findsNothing);
  });

  testWidgets('My lost pets reloads after a mutation during an earlier request',
      (tester) async {
    final apiClient = FakeApiClient();
    final first = Completer<Object?>();
    final second = Completer<Object?>();
    var reads = 0;
    apiClient.setHandler('GET', 'lost-pets/mine', (_) {
      reads++;
      return reads == 1 ? first.future : second.future;
    });
    final container = _container(apiClient);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: MyLostPetsScreen()),
    ));
    await tester.pump();
    expect(reads, 1);

    container.read(postMutationRevisionProvider.notifier).state++;
    await tester.pump();
    first.complete({
      'items': [_pet(resolved: false)],
      'next_cursor': null,
      'limit': 50,
    });
    await tester.pump();
    expect(reads, 2);

    second.complete({
      'items': [_pet(resolved: true)],
      'next_cursor': null,
      'limit': 50,
    });
    await tester.pumpAndSettle();
    expect(find.text('Reunited'), findsOneWidget);
    expect(find.text('Missing'), findsNothing);
  });

  testWidgets('My lost pets keeps successful mutation state when refresh fails',
      (tester) async {
    final apiClient = FakeApiClient();
    var reads = 0;
    apiClient.setHandler('GET', 'lost-pets/mine', (_) {
      reads++;
      if (reads > 1) throw StateError('Archive refresh unavailable');
      return {
        'items': [_pet(resolved: false)],
        'next_cursor': null,
        'limit': 50,
      };
    });
    final container = _container(apiClient);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: MyLostPetsScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Mittens'), findsOneWidget);

    final updated = LostPetData.fromJson({
      ..._pet(resolved: true),
      'pet_name': 'Updated Mittens',
    });
    container.read(lostPetMutationOverridesProvider.notifier).state = {
      'pet-1': updated,
    };
    container.read(postMutationRevisionProvider.notifier).state++;
    await tester.pump();
    expect(find.text('Updated Mittens'), findsOneWidget);
    expect(find.text('Reunited'), findsOneWidget);

    container.read(deletedLostPetIdsProvider.notifier).state = {'pet-1'};
    await tester.pump();
    expect(find.text('Updated Mittens'), findsNothing);
  });

  testWidgets('rapid Contact Owner taps send one backend request',
      (tester) async {
    final apiClient = FakeApiClient();
    final contact = Completer<Object?>();
    apiClient.setHandler(
        'GET', 'lost-pets/pet-1', (_) => _pet(resolved: false));
    apiClient.setHandler('GET', 'lost-pets/pet-1/comments',
        (_) => {'items': <Object>[], 'next_cursor': null, 'limit': 20});
    apiClient.setHandler(
        'POST', 'lost-pets/pet-1/contact', (_) => contact.future);
    final container = _container(apiClient);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: LostPetDetailScreen(lostPetId: 'pet-1')),
    ));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Contact Owner'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Contact Owner'), findsOneWidget);

    await tester.tap(find.text('Contact Owner'));
    await tester.tap(find.text('Contact Owner'));
    await tester.pump();
    expect(
      apiClient.calls
          .where((call) => call.path == 'lost-pets/pet-1/contact')
          .length,
      1,
    );

    contact.complete(null);
    await tester.pumpAndSettle();
  });
}
