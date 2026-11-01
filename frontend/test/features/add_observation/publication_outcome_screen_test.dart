import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as image;
import 'package:mushukistan_frontend/core/localization/app_strings.dart';
import 'package:mushukistan_frontend/core/localization/language_controller.dart';
import 'package:mushukistan_frontend/core/network/api_error.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';
import 'package:mushukistan_frontend/core/storage/token_store.dart';
import 'package:mushukistan_frontend/core/storage/token_store_provider.dart';
import 'package:mushukistan_frontend/features/add_observation/application/add_observation_controller.dart';
import 'package:mushukistan_frontend/features/add_observation/presentation/screens/add_observation_details_screen.dart';

import '../../support/fakes.dart';

void main() {
  testWidgets(
      'account transition clears visible draft and ignores its late error',
      (tester) async {
    final store = GuardedAuthTokenStore(InMemoryAuthTokenStore());
    await store.write('synthetic-account-A');
    final api = FakeApiClient();
    final reply = Completer<Object?>();
    api.setHandler('POST', 'posts', (_) => reply.future);
    final container = ProviderContainer(overrides: [
      mushukistanApiProvider.overrideWithValue(MushukistanApi(client: api)),
      tokenStoreProvider.overrideWithValue(store),
    ]);
    addTearDown(container.dispose);
    final controller =
        container.read(addObservationControllerProvider.notifier);
    controller.setPhoto(
        bytes: image.encodeJpg(image.Image(width: 4, height: 4)),
        filename: 'private.jpg',
        contentType: 'image/jpeg');
    controller.setCatName('Account A private draft');
    final router = GoRouter(routes: [
      GoRoute(
          path: '/', builder: (_, __) => const AddObservationDetailsScreen())
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container, child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();
    final id = controller.state.publicationId;
    final pending =
        controller.submit(strings: AppStrings.forLanguage(AppLanguage.english));
    final rejected =
        expectLater(pending, throwsA(isA<MushukistanApiException>()));
    await store.write('synthetic-account-B');
    await tester.pumpAndSettle();
    expect(controller.state.publicationId, isNot(id));
    expect(controller.state.hasDraft, isFalse);
    expect(find.text('Account A private draft'), findsNothing);
    reply.completeError(const MushukistanApiException(
        kind: ApiFailureKind.network,
        code: 'PHOTO_UPLOAD_TIMEOUT',
        message: 'Timeout'));
    await rejected;
    await tester.pumpAndSettle();
    expect(controller.state.hasDraft, isFalse);
    expect(controller.state.outcomeUnknown, isFalse);
    expect(controller.state.errorMessage, isNull);
  });
  testWidgets(
      'uncertain submission retains draft and locks edits while checking status',
      (tester) async {
    final api = FakeApiClient();
    api.setHandler(
        'POST',
        'posts',
        (_) => throw const MushukistanApiException(
            kind: ApiFailureKind.network,
            code: 'PHOTO_UPLOAD_TIMEOUT',
            message: 'Timeout'));
    final container = ProviderContainer(overrides: [
      mushukistanApiProvider.overrideWithValue(MushukistanApi(client: api)),
      appLanguageProvider.overrideWith((ref) => AppLanguage.english),
    ]);
    addTearDown(container.dispose);
    final controller =
        container.read(addObservationControllerProvider.notifier);
    controller.setPhoto(
        bytes: image.encodeJpg(image.Image(width: 4, height: 4)),
        filename: 'test.jpg',
        contentType: 'image/jpeg');
    controller.setCatName('Draft name');
    controller.setDescription('Draft details');
    final id = controller.state.publicationId;
    await expectLater(
        controller.submit(strings: AppStrings.forLanguage(AppLanguage.english)),
        throwsA(isA<MushukistanApiException>()));
    final router = GoRouter(initialLocation: '/add/details', routes: [
      GoRoute(
          path: '/add/details',
          builder: (_, __) => const AddObservationDetailsScreen()),
      GoRoute(path: '/feed', builder: (_, __) => const Text('Feed')),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container, child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();
    expect(controller.state.outcomeUnknown, isTrue);
    expect(controller.state.publicationId, id);
    expect(controller.state.catName, 'Draft name');
    expect(controller.state.description, 'Draft details');
    await tester.scrollUntilVisible(find.text('Check publication status'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Check publication status'), findsOneWidget);
    for (final element in find.byType(TextFormField).evaluate()) {
      expect((element.widget as TextFormField).enabled, isFalse);
    }
  });
}
