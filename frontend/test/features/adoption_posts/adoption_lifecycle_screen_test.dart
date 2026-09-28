import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';
import 'package:mushukistan_frontend/features/adoption_posts/presentation/screens/adoption_post_detail_screen.dart';
import 'package:mushukistan_frontend/features/adoption_posts/presentation/screens/adoption_post_create_screen.dart';
import 'package:mushukistan_frontend/features/adoption_posts/presentation/screens/adoption_post_edit_screen.dart';
import 'package:mushukistan_frontend/features/adoption_posts/presentation/screens/my_adoption_posts_screen.dart';
import 'package:mushukistan_frontend/features/auth/application/auth_controller.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_models.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_repository.dart';
import 'package:mushukistan_frontend/features/feed/presentation/screens/feed_screen.dart';

import '../../support/fakes.dart';

ProviderContainer _container(FakeApiClient apiClient,
        {String? userId = 'owner-1'}) =>
    ProviderContainer(overrides: [
      mushukistanApiProvider
          .overrideWithValue(MushukistanApi(client: apiClient)),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(
        restoreResult: userId == null
            ? const SessionRestoreMissing()
            : SessionRestoreSuccess(AuthSession.restored(
                accessToken: 'token', user: testUser(id: userId))),
      )),
      googleIdentityTokenProvider.overrideWithValue(
        FakeGoogleIdentityTokenProvider(),
      ),
    ]);

Map<String, Object?> _post({bool resolved = false}) => {
      'id': 'adoption-1',
      'pet_name': 'Mittens',
      'author': {'id': 'owner-1', 'name': 'Owner'},
      'owner_phone_number': '+998 90 123 45 67',
      'photo_url': 'https://example.com/pet.jpg',
      'photo_urls': ['https://example.com/pet.jpg'],
      'created_at': '2026-09-28T09:00:00Z',
      'is_resolved': resolved,
      'comment_count': 0,
    };

void main() {
  testWidgets('creation explains contact without a mandatory checkbox',
      (tester) async {
    final container = _container(FakeApiClient());
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: AdoptionPostCreateScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(CheckboxListTile), findsNothing);
    await tester.scrollUntilVisible(find.textContaining('Contact Owner'), 250,
        scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('Contact Owner'), findsOneWidget);
  });

  testWidgets('only owner sees edit and delete on a rehomed post',
      (tester) async {
    final apiClient = FakeApiClient();
    apiClient.setHandler(
        'GET', 'adoption-posts/adoption-1', (_) => _post(resolved: true));
    apiClient.setHandler('GET', 'adoption-posts/adoption-1/comments',
        (_) => {'items': <Object>[], 'next_cursor': null, 'limit': 20});
    final owner = _container(apiClient);
    addTearDown(owner.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: owner,
      child: const MaterialApp(
          home: AdoptionPostDetailScreen(adoptionPostId: 'adoption-1')),
    ));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Edit rehoming post'), 250,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Edit rehoming post'), findsOneWidget);
    expect(find.text('Delete rehoming post'), findsOneWidget);
    expect(find.text('Contact Owner'), findsNothing);
  });

  testWidgets('another user cannot see owner controls', (tester) async {
    final apiClient = FakeApiClient();
    apiClient.setHandler(
        'GET', 'adoption-posts/adoption-1', (_) => _post(resolved: true));
    apiClient.setHandler('GET', 'adoption-posts/adoption-1/comments',
        (_) => {'items': <Object>[], 'next_cursor': null, 'limit': 20});
    final other = _container(apiClient, userId: 'other-1');
    addTearDown(other.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: other,
      child: const MaterialApp(
          home: AdoptionPostDetailScreen(adoptionPostId: 'adoption-1')),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Edit rehoming post'), findsNothing);
    expect(find.text('Delete rehoming post'), findsNothing);
  });

  testWidgets('delete requires confirmation', (tester) async {
    final apiClient = FakeApiClient();
    apiClient.setHandler('GET', 'adoption-posts/adoption-1', (_) => _post());
    apiClient.setHandler('GET', 'adoption-posts/adoption-1/comments',
        (_) => {'items': <Object>[], 'next_cursor': null, 'limit': 20});
    final container = _container(apiClient);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
          home: AdoptionPostDetailScreen(adoptionPostId: 'adoption-1')),
    ));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Delete rehoming post'), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Delete rehoming post'));
    await tester.pumpAndSettle();
    expect(find.text('This rehoming post will be removed.'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(apiClient.calls.where((call) => call.method == 'DELETE'), isEmpty);
  });

  testWidgets('confirmed delete removes the post from local state',
      (tester) async {
    final apiClient = FakeApiClient();
    apiClient.setHandler('GET', 'adoption-posts/adoption-1', (_) => _post());
    apiClient.setHandler('GET', 'adoption-posts/adoption-1/comments',
        (_) => {'items': <Object>[], 'next_cursor': null, 'limit': 20});
    apiClient.setHandler('DELETE', 'adoption-posts/adoption-1', (_) => null);
    final container = _container(apiClient);
    addTearDown(container.dispose);
    final router = GoRouter(initialLocation: '/archive', routes: [
      GoRoute(
          path: '/archive',
          builder: (context, state) => Scaffold(
                body: TextButton(
                    onPressed: () => context.push('/adoption-posts/adoption-1'),
                    child: const Text('Open')),
              )),
      GoRoute(
          path: '/adoption-posts/:id',
          builder: (context, state) =>
              const AdoptionPostDetailScreen(adoptionPostId: 'adoption-1')),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Delete rehoming post'), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Delete rehoming post'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(container.read(deletedAdoptionIdsProvider), contains('adoption-1'));
    expect(apiClient.calls.where((call) => call.method == 'DELETE').length, 1);
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('guest cannot see owner controls', (tester) async {
    final apiClient = FakeApiClient();
    apiClient.setHandler(
        'GET', 'adoption-posts/adoption-1', (_) => _post(resolved: true));
    apiClient.setHandler('GET', 'adoption-posts/adoption-1/comments',
        (_) => {'items': <Object>[], 'next_cursor': null, 'limit': 20});
    final guest = _container(apiClient, userId: null);
    addTearDown(guest.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: guest,
      child: const MaterialApp(
          home: AdoptionPostDetailScreen(adoptionPostId: 'adoption-1')),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Edit rehoming post'), findsNothing);
    expect(find.text('Delete rehoming post'), findsNothing);
  });

  testWidgets('rapid Contact Owner taps make one request', (tester) async {
    final apiClient = FakeApiClient();
    final contact = Completer<Object?>();
    apiClient.setHandler('GET', 'adoption-posts/adoption-1', (_) => _post());
    apiClient.setHandler('GET', 'adoption-posts/adoption-1/comments',
        (_) => {'items': <Object>[], 'next_cursor': null, 'limit': 20});
    apiClient.setHandler(
        'POST', 'adoption-posts/adoption-1/contact', (_) => contact.future);
    final container = _container(apiClient, userId: 'other-1');
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
          home: AdoptionPostDetailScreen(adoptionPostId: 'adoption-1')),
    ));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Contact Owner'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Contact Owner'));
    await tester.tap(find.text('Contact Owner'));
    await tester.pump();
    expect(
        apiClient.calls
            .where((call) => call.path == 'adoption-posts/adoption-1/contact')
            .length,
        1);
    contact.complete(null);
    await tester.pumpAndSettle();
  });

  testWidgets('guest Contact Owner requests sign-in without recording contact',
      (tester) async {
    final apiClient = FakeApiClient();
    apiClient.setHandler('GET', 'adoption-posts/adoption-1', (_) => _post());
    apiClient.setHandler('GET', 'adoption-posts/adoption-1/comments',
        (_) => {'items': <Object>[], 'next_cursor': null, 'limit': 20});
    final container = _container(apiClient, userId: null);
    addTearDown(container.dispose);
    final router =
        GoRouter(initialLocation: '/adoption-posts/adoption-1', routes: [
      GoRoute(
          path: '/adoption-posts/:id',
          builder: (context, state) =>
              const AdoptionPostDetailScreen(adoptionPostId: 'adoption-1')),
      GoRoute(
          path: '/auth-required',
          builder: (context, state) =>
              const Scaffold(body: Text('Sign in required'))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Contact Owner'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Contact Owner'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in required'), findsOneWidget);
    expect(
        apiClient.calls
            .where((call) => call.path == 'adoption-posts/adoption-1/contact'),
        isEmpty);
  });

  testWidgets('owner archive includes a rehomed post', (tester) async {
    final apiClient = FakeApiClient();
    apiClient.setHandler(
        'GET',
        'adoption-posts/mine',
        (_) => {
              'items': [_post(resolved: true)],
              'next_cursor': null,
              'limit': 50,
            });
    final container = _container(apiClient);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: MyAdoptionPostsScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Mittens'), findsOneWidget);
    expect(find.text('Rehomed'), findsOneWidget);
  });

  testWidgets('edit screen preloads mutable fields', (tester) async {
    final apiClient = FakeApiClient();
    apiClient.setHandler(
        'GET',
        'adoption-posts/adoption-1',
        (_) => {
              ..._post(resolved: true),
              'additional_info': 'Needs a quiet home',
              'owner_telegram_username': 'mittens_owner',
            });
    final container = _container(apiClient);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
          home: AdoptionPostEditScreen(adoptionPostId: 'adoption-1')),
    ));
    await tester.pumpAndSettle();
    expect(
        find.byWidgetPredicate((widget) =>
            widget is TextFormField && widget.controller?.text == 'Mittens'),
        findsOneWidget);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -800));
    await tester.pumpAndSettle();
    expect(
        find.byWidgetPredicate((widget) =>
            widget is TextFormField &&
            widget.controller?.text == '+998 90 123 45 67'),
        findsOneWidget);
    expect(
        find.byWidgetPredicate((widget) =>
            widget is TextFormField &&
            widget.controller?.text == 'Needs a quiet home'),
        findsOneWidget);
  });

  testWidgets('successful edit publishes the updated post to local surfaces',
      (tester) async {
    final apiClient = FakeApiClient();
    apiClient.setHandler('GET', 'adoption-posts/adoption-1', (_) => _post());
    apiClient.setHandler(
        'PATCH',
        'adoption-posts/adoption-1',
        (_) => {
              ..._post(),
              'pet_name': 'Updated Mittens',
            });
    final container = _container(apiClient);
    addTearDown(container.dispose);
    final router = GoRouter(initialLocation: '/archive', routes: [
      GoRoute(
          path: '/archive',
          builder: (context, state) => Scaffold(
                body: TextButton(
                    onPressed: () =>
                        context.push('/adoption-posts/adoption-1/edit'),
                    child: const Text('Open edit')),
              )),
      GoRoute(
          path: '/adoption-posts/:id/edit',
          builder: (context, state) => const AdoptionPostEditScreen(
                adoptionPostId: 'adoption-1',
              )),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.tap(find.text('Open edit'));
    await tester.pumpAndSettle();
    final nameField = find.byWidgetPredicate((widget) =>
        widget is TextFormField && widget.controller?.text == 'Mittens');
    await tester.enterText(nameField, 'Updated Mittens');
    await tester.scrollUntilVisible(find.text('Save changes'), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(
        container
            .read(adoptionMutationOverridesProvider)['adoption-1']
            ?.petName,
        'Updated Mittens');
    expect(container.read(postMutationRevisionProvider), 1);
    expect(
        apiClient.calls
            .where((call) =>
                call.path == 'adoption-posts/adoption-1' &&
                call.method == 'PATCH')
            .length,
        1);
    expect(find.text('Open edit'), findsOneWidget);
  });

  testWidgets('archive queues refresh requested while a load is running',
      (tester) async {
    final apiClient = FakeApiClient();
    final first = Completer<Object?>();
    final second = Completer<Object?>();
    var reads = 0;
    apiClient.setHandler('GET', 'adoption-posts/mine', (_) {
      reads++;
      return reads == 1 ? first.future : second.future;
    });
    final container = _container(apiClient);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: MyAdoptionPostsScreen()),
    ));
    await tester.pump();
    expect(reads, 1);
    container.read(postMutationRevisionProvider.notifier).state++;
    await tester.pump();
    first.complete({
      'items': [_post()],
      'next_cursor': null,
      'limit': 50
    });
    await tester.pump();
    expect(reads, 2);
    second.complete({
      'items': [_post(resolved: true)],
      'next_cursor': null,
      'limit': 50
    });
    await tester.pumpAndSettle();
    expect(find.text('Rehomed'), findsOneWidget);
    expect(find.text('Looking for a home'), findsNothing);
  });

  testWidgets('archive applies successful mutation despite refresh failure',
      (tester) async {
    final apiClient = FakeApiClient();
    var reads = 0;
    apiClient.setHandler('GET', 'adoption-posts/mine', (_) {
      reads++;
      if (reads > 1) throw StateError('Archive refresh unavailable');
      return {
        'items': [_post()],
        'next_cursor': null,
        'limit': 50
      };
    });
    final container = _container(apiClient);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: MyAdoptionPostsScreen()),
    ));
    await tester.pumpAndSettle();
    container.read(adoptionMutationOverridesProvider.notifier).state = {
      'adoption-1': AdoptionPostData.fromJson(_post(resolved: true)),
    };
    container.read(postMutationRevisionProvider.notifier).state++;
    await tester.pump();
    expect(find.text('Rehomed'), findsOneWidget);
    container.read(deletedAdoptionIdsProvider.notifier).state = {'adoption-1'};
    await tester.pump();
    expect(find.text('Mittens'), findsNothing);
  });

  testWidgets('Feed applies rehoming edit, resolution and delete locally',
      (tester) async {
    final apiClient = FakeApiClient();
    var failRefresh = false;
    apiClient.setHandler('GET', 'adoption-posts', (_) {
      if (failRefresh) throw StateError('Feed refresh unavailable');
      return {
        'items': [_post()],
        'next_cursor': null,
        'limit': 30
      };
    });
    final container = _container(apiClient);
    addTearDown(container.dispose);
    container.read(feedModeProvider.notifier).state = 'adoption';
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: FeedScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Mittens', findRichText: true), findsOneWidget);

    final edited = AdoptionPostData.fromJson({
      ..._post(),
      'pet_name': 'Updated Mittens',
    });
    container.read(adoptionMutationOverridesProvider.notifier).state = {
      'adoption-1': edited,
    };
    failRefresh = true;
    container.read(postMutationRevisionProvider.notifier).state++;
    await tester.pump();
    expect(find.textContaining('Updated Mittens', findRichText: true),
        findsOneWidget);

    container.read(resolvedAdoptionIdsProvider.notifier).state = {'adoption-1'};
    container.read(postMutationRevisionProvider.notifier).state++;
    await tester.pump();
    expect(find.textContaining('Updated Mittens', findRichText: true),
        findsNothing);
    await tester.pumpAndSettle();
    expect(find.textContaining('Updated Mittens', findRichText: true),
        findsNothing);

    container.read(resolvedAdoptionIdsProvider.notifier).state = {};
    container.read(deletedAdoptionIdsProvider.notifier).state = {'adoption-1'};
    await tester.pump();
    expect(find.textContaining('Updated Mittens', findRichText: true),
        findsNothing);
  });
}
