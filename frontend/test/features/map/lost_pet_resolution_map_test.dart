import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
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

  testWidgets(
      'edited and deleted Lost Pet markers reconcile locally after refresh failure',
      (tester) async {
    final apiClient = FakeApiClient();
    const emptyPage = {'items': <Object>[], 'next_cursor': null, 'limit': 100};
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
    const markerKey = ValueKey<String>('marker:lostPets:pet-1');
    expect(find.byKey(markerKey), findsOneWidget);

    container.read(lostPetMutationOverridesProvider.notifier).state = {
      'pet-1': LostPetData.fromJson({
        'id': 'pet-1',
        'pet_name': 'Updated Mittens',
        'owner_phone_number': '+998 90 123 45 67',
        'photo_url': 'https://example.com/pet.jpg',
        'photo_urls': ['https://example.com/pet.jpg'],
        'last_seen_location': {'latitude': 41.305, 'longitude': 69.255},
        'created_at': '2026-09-28T09:00:00Z',
        'is_resolved': false,
        'comment_count': 0,
      }),
    };
    container.read(postMutationRevisionProvider.notifier).state++;
    await tester.pump();
    final mapMarkers = tester
        .widgetList<MarkerLayer>(find.byType(MarkerLayer))
        .expand((layer) => layer.markers);
    final petMarker =
        mapMarkers.firstWhere((marker) => marker.key == markerKey);
    expect(petMarker.point.latitude, 41.305);
    expect(petMarker.point.longitude, 69.255);

    container.read(deletedLostPetIdsProvider.notifier).state = {'pet-1'};
    container.read(postMutationRevisionProvider.notifier).state++;
    await tester.pump();
    expect(find.byKey(markerKey), findsNothing);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(mapReads, greaterThan(1));
    expect(find.byKey(markerKey), findsNothing);
  });
}
