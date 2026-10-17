import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mushukistan_frontend/core/network/api_error.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';
import 'package:mushukistan_frontend/features/auth/application/auth_controller.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_models.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_repository.dart';
import 'package:mushukistan_frontend/features/lost_pets/presentation/screens/lost_pet_detail_screen.dart';

import '../../support/fakes.dart';

Map<String, Object?> _pet({String? phone, bool contactAvailable = true}) => {
      'id': 'pet-1',
      'pet_name': 'Mittens',
      'author': {'id': 'owner-1', 'name': 'Owner'},
      if (phone != null) 'owner_phone_number': phone,
      'contact_available': contactAvailable,
      'photo_url': 'https://example.com/pet.jpg',
      'photo_urls': ['https://example.com/pet.jpg'],
      'last_seen_location': {'latitude': 41.3, 'longitude': 69.25},
      'created_at': '2026-09-28T09:00:00Z',
      'is_resolved': false,
      'comment_count': 0,
    };

ProviderContainer _container(FakeApiClient client, {required bool signedIn}) =>
    ProviderContainer(overrides: [
      mushukistanApiProvider.overrideWithValue(MushukistanApi(client: client)),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(
        restoreResult: signedIn
            ? SessionRestoreSuccess(AuthSession.restored(
                accessToken: 'token',
                user: testUser(id: '11111111-1111-4111-8111-111111111111'),
              ))
            : const SessionRestoreMissing(),
      )),
      googleIdentityTokenProvider
          .overrideWithValue(FakeGoogleIdentityTokenProvider()),
    ]);

void main() {
  test('contact_available is parsed, with a fallback for older servers', () {
    final base = _pet();
    expect(LostPetData.fromJson(base).contactAvailable, isTrue);
    expect(LostPetData.fromJson(_pet(contactAvailable: false)).contactAvailable,
        isFalse);
    final legacy = {..._pet(phone: '+998 90 123 45 67')}
      ..remove('contact_available');
    expect(LostPetData.fromJson(legacy).contactAvailable, isTrue);
    final legacyWithout = {..._pet()}..remove('contact_available');
    expect(LostPetData.fromJson(legacyWithout).contactAvailable, isFalse);
  });

  testWidgets(
      'guest sees Contact Owner without the number and is sent to sign in',
      (tester) async {
    final client = FakeApiClient()
      ..setHandler('GET', 'lost-pets/pet-1', (_) => _pet())
      ..setHandler('GET', 'lost-pets/pet-1/comments',
          (_) => {'items': <Object>[], 'next_cursor': null, 'limit': 20});
    final container = _container(client, signedIn: false);
    addTearDown(container.dispose);
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const LostPetDetailScreen(lostPetId: 'pet-1'),
      ),
      GoRoute(
        path: '/auth-required',
        builder: (_, __) => const Scaffold(body: Text('Sign in required')),
      ),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Contact Owner'), findsOneWidget);
    expect(find.textContaining('+998'), findsNothing);
    await tester.ensureVisible(find.text('Contact Owner'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Contact Owner'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in required'), findsOneWidget);
    expect(client.calls.where((c) => c.path.endsWith('/contact')), isEmpty,
        reason: 'no contact event is recorded for guests');
  });

  testWidgets('signed-in viewer sees the number on the Contact Owner button',
      (tester) async {
    final client = FakeApiClient()
      ..setHandler(
          'GET', 'lost-pets/pet-1', (_) => _pet(phone: '+998 90 123 45 67'))
      ..setHandler('GET', 'lost-pets/pet-1/comments',
          (_) => {'items': <Object>[], 'next_cursor': null, 'limit': 20});
    final container = _container(client, signedIn: true);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: LostPetDetailScreen(lostPetId: 'pet-1')),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Contact Owner'), findsOneWidget);
    expect(find.text('+998 90 123 45 67'), findsOneWidget);
  });

  testWidgets(
      'signed-in viewer asks the server to reveal the contact, then records the contact',
      (tester) async {
    final client = FakeApiClient()
      ..setHandler('GET', 'lost-pets/pet-1', (_) => _pet())
      ..setHandler('GET', 'lost-pets/pet-1/comments',
          (_) => {'items': <Object>[], 'next_cursor': null, 'limit': 20})
      ..setHandler(
          'POST',
          'lost-pets/pet-1/contact-reveal',
          (_) => {
                'phone_number': '+998 90 123 45 67',
                'telegram_username': 'owner_handle',
              })
      ..setHandler('POST', 'lost-pets/pet-1/contact', (_) => null);
    final container = _container(client, signedIn: true);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: LostPetDetailScreen(lostPetId: 'pet-1')),
    ));
    await tester.pumpAndSettle();

    // Nothing private is on screen, or in the response, before the explicit request.
    expect(find.text('Contact Owner'), findsOneWidget);
    expect(find.textContaining('+998'), findsNothing);
    expect(find.textContaining('owner_handle'), findsNothing);

    await tester.ensureVisible(find.text('Contact Owner'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Contact Owner'));
    await tester.pumpAndSettle();

    final paths = client.calls
        .where((c) => c.method == 'POST')
        .map((c) => c.path)
        .toList();
    expect(
        paths, ['lost-pets/pet-1/contact-reveal', 'lost-pets/pet-1/contact']);
    expect(find.text('+998 90 123 45 67'), findsOneWidget);
    expect(find.text('@owner_handle'), findsOneWidget);
  });

  testWidgets('reaching the reveal limit explains it and records no contact',
      (tester) async {
    final client = FakeApiClient()
      ..setHandler('GET', 'lost-pets/pet-1', (_) => _pet())
      ..setHandler('GET', 'lost-pets/pet-1/comments',
          (_) => {'items': <Object>[], 'next_cursor': null, 'limit': 20})
      ..setHandler('POST', 'lost-pets/pet-1/contact-reveal', (_) {
        throw const MushukistanApiException(
          kind: ApiFailureKind.unknown,
          statusCode: 429,
          code: 'CONTACT_REVEAL_LIMIT',
          message: 'limit',
        );
      });
    final container = _container(client, signedIn: true);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: LostPetDetailScreen(lostPetId: 'pet-1')),
    ));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Contact Owner'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Contact Owner'));
    await tester.pumpAndSettle();

    expect(find.textContaining('maximum number of owner contacts'),
        findsOneWidget);
    expect(client.calls.where((c) => c.path.endsWith('/contact')), isEmpty);
    expect(find.textContaining('+998'), findsNothing);
  });

  test('every request declares reveal mode', () {
    // The header is what stops the server from sending contacts with post details.
    final source = File('lib/core/network/api_client.dart').readAsStringSync();
    expect(source, contains("'x-contact-mode': 'reveal'"));
  });

  testWidgets('no contact action when the owner cannot be contacted',
      (tester) async {
    final client = FakeApiClient()
      ..setHandler(
          'GET', 'lost-pets/pet-1', (_) => _pet(contactAvailable: false))
      ..setHandler('GET', 'lost-pets/pet-1/comments',
          (_) => {'items': <Object>[], 'next_cursor': null, 'limit': 20});
    final container = _container(client, signedIn: false);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: LostPetDetailScreen(lostPetId: 'pet-1')),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Contact Owner'), findsNothing);
  });
}
