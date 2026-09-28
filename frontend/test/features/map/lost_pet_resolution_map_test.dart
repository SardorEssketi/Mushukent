import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';
import 'package:mushukistan_frontend/features/map/presentation/screens/map_screen.dart';

import '../../support/fakes.dart';

void main() {
  testWidgets('resolved pet marker disappears even when Map reload fails',
      (tester) async {
    final apiClient = FakeApiClient();
    final emptyPage = {'items': <Object>[], 'next_cursor': null, 'limit': 100};
    apiClient.setHandler('GET', 'cats', (_) => emptyPage);
    apiClient.setHandler('GET', 'places', (_) => emptyPage);
    var mapReads = 0;
    apiClient.setHandler('GET', 'lost-pets/map', (_) {
      mapReads++;
      if (mapReads > 1) throw StateError('Map reload unavailable');
      return {
        'items': [
          {
            'id': 'pet-1',
            'pet_name': 'Mittens',
            'last_seen_location': {'latitude': 41.3, 'longitude': 69.25},
            'is_resolved': false,
            'created_at': '2026-09-28T09:00:00Z',
          }
        ],
        'next_cursor': null,
        'limit': 100,
      };
    });
    final container = ProviderContainer(overrides: [
      mushukistanApiProvider
          .overrideWithValue(MushukistanApi(client: apiClient)),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: MapScreen()),
    ));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(mapReads, 1);
    const markerKey = ValueKey<String>('marker:lostPets:pet-1');
    expect(find.byKey(markerKey), findsOneWidget);

    container.read(resolvedLostPetIdsProvider.notifier).state = {'pet-1'};
    container.read(postMutationRevisionProvider.notifier).state++;
    await tester.pump();
    expect(find.byKey(markerKey), findsNothing);

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(mapReads, greaterThan(1));
    expect(find.byKey(markerKey), findsNothing);
  });
}
