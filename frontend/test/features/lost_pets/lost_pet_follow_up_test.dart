import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/core/network/api_error.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';
import 'package:mushukistan_frontend/features/auth/application/auth_controller.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_models.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_repository.dart';
import 'package:mushukistan_frontend/features/feed/presentation/screens/feed_screen.dart';
import 'package:mushukistan_frontend/features/lost_pets/presentation/widgets/lost_pet_follow_up_listener.dart';

import '../../support/fakes.dart';

void main() {
  testWidgets(
      'owner answer updates shared post revision and sends only Yes or No',
      (tester) async {
    final apiClient = FakeApiClient();
    const followUpId = 'follow-up-1';
    const petId = 'lost-pet-1';
    apiClient.setHandler(
      'GET',
      'feed',
      (_) => {'items': <Object>[], 'next_cursor': null, 'limit': 30},
    );
    apiClient.setHandler(
        'GET',
        'lost-pets/follow-ups/due',
        (_) => [
              {
                'id': followUpId,
                'lost_pet_id': petId,
                'pet_name': 'Mittens',
                'due_at': '2026-09-28T10:00:00Z',
              }
            ]);
    apiClient.setHandler(
      'POST',
      'lost-pets/follow-ups/$followUpId/answer',
      (_) => {
        'id': petId,
        'pet_name': 'Mittens',
        'owner_phone_number': '+998 90 123 45 67',
        'photo_url': 'https://example.com/pet.jpg',
        'photo_urls': ['https://example.com/pet.jpg'],
        'last_seen_location': {'latitude': 41.3, 'longitude': 69.2},
        'created_at': '2026-09-28T09:00:00Z',
        'is_resolved': true,
        'comment_count': 0,
      },
    );
    final container = ProviderContainer(overrides: [
      mushukistanApiProvider
          .overrideWithValue(MushukistanApi(client: apiClient)),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(
        restoreResult: SessionRestoreSuccess(
          AuthSession.restored(accessToken: 'token', user: testUser()),
        ),
      )),
      googleIdentityTokenProvider.overrideWithValue(
        FakeGoogleIdentityTokenProvider(),
      ),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: LostPetFollowUpListener(
          child: _FeedRevisionObserver(),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Did you find your pet?'), findsOneWidget);
    expect(find.text('Yes'), findsOneWidget);
    expect(find.text('No'), findsOneWidget);
    expect(container.read(postMutationRevisionProvider), 0);
    final feedReadsBefore =
        apiClient.calls.where((call) => call.path == 'feed').length;

    await tester.tap(find.text('Yes'));
    await tester.pumpAndSettle();

    final answerCalls = apiClient.calls.where(
      (call) => call.path == 'lost-pets/follow-ups/$followUpId/answer',
    );
    expect(answerCalls.length, 1);
    expect(answerCalls.single.body, {'answer': 'yes'});
    expect(container.read(postMutationRevisionProvider), 1);
    expect(container.read(resolvedLostPetIdsProvider), contains(petId));
    expect(apiClient.calls.where((call) => call.path == 'feed').length,
        greaterThan(feedReadsBefore));
    expect(find.text('Did you find your pet?'), findsNothing);
  });

  testWidgets(
      'completed response closes stale prompt and checks remaining due pets',
      (tester) async {
    final apiClient = FakeApiClient();
    var dueReads = 0;
    apiClient.setHandler('GET', 'feed',
        (_) => {'items': <Object>[], 'next_cursor': null, 'limit': 30});
    apiClient.setHandler('GET', 'lost-pets/follow-ups/due', (_) {
      dueReads++;
      return [
        {
          'id': dueReads == 1 ? 'stale' : 'next',
          'lost_pet_id': dueReads == 1 ? 'pet-1' : 'pet-2',
          'pet_name': dueReads == 1 ? 'Mittens' : 'Snowball',
          'due_at': '2026-09-28T10:00:00Z',
        }
      ];
    });
    apiClient.setHandler('POST', 'lost-pets/follow-ups/stale/answer', (_) {
      throw const MushukistanApiException(
        kind: ApiFailureKind.conflict,
        statusCode: 409,
        code: 'FOLLOW_UP_COMPLETED',
        message: 'Already answered.',
      );
    });
    apiClient.setHandler(
        'POST',
        'lost-pets/follow-ups/next/answer',
        (_) => {
              'id': 'pet-2',
              'pet_name': 'Snowball',
              'owner_phone_number': '+998 90 123 45 67',
              'photo_url': 'https://example.com/pet.jpg',
              'photo_urls': ['https://example.com/pet.jpg'],
              'last_seen_location': {'latitude': 41.3, 'longitude': 69.2},
              'created_at': '2026-09-28T09:00:00Z',
              'is_resolved': false,
              'comment_count': 0,
            });
    final container = ProviderContainer(overrides: [
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
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: LostPetFollowUpListener(child: _FeedRevisionObserver()),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Mittens'), findsOneWidget);

    await tester.tap(find.text('Yes'));
    await tester.pumpAndSettle();
    expect(dueReads, 2);
    expect(find.text('Mittens'), findsNothing);
    expect(find.text('Snowball'), findsOneWidget);
    expect(container.read(postMutationRevisionProvider), 1);

    await tester.tap(find.text('No'));
    await tester.pumpAndSettle();
    expect(find.text('Did you find your pet?'), findsNothing);
    expect(container.read(postMutationRevisionProvider), 2);
    expect(container.read(resolvedLostPetIdsProvider), isEmpty);
    expect(
        apiClient.calls
            .where((call) => call.path == 'lost-pets/follow-ups/stale/answer')
            .length,
        1);
    expect(
        apiClient.calls
            .where((call) => call.path == 'lost-pets/follow-ups/next/answer')
            .single
            .body,
        {'answer': 'no'});
  });
}

class _FeedRevisionObserver extends ConsumerWidget {
  const _FeedRevisionObserver();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(feedPostsProvider);
    return const Scaffold(body: Text('Home'));
  }
}
