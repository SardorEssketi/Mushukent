import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';
import 'package:mushukistan_frontend/features/auth/application/auth_controller.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_models.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_repository.dart';
import 'package:mushukistan_frontend/features/lost_pets/presentation/screens/lost_pet_detail_screen.dart';
import 'package:mushukistan_frontend/features/lost_pets/presentation/screens/my_lost_pets_screen.dart';

import '../../support/fakes.dart';

ProviderContainer _container(FakeApiClient apiClient) =>
    ProviderContainer(overrides: [
      mushukistanApiProvider
          .overrideWithValue(MushukistanApi(client: apiClient)),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(
        restoreResult: SessionRestoreSuccess(
          AuthSession.restored(accessToken: 'token', user: testUser()),
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
      'photo_url': 'https://example.com/pet.jpg',
      'photo_urls': ['https://example.com/pet.jpg'],
      'last_seen_location': {'latitude': 41.3, 'longitude': 69.25},
      'created_at': '2026-09-28T09:00:00Z',
      'is_resolved': resolved,
      'comment_count': 0,
    };

void main() {
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
