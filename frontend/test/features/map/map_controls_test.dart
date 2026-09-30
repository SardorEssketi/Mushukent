import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';
import 'package:mushukistan_frontend/features/map/presentation/screens/map_screen.dart';
import 'package:mushukistan_frontend/features/map/presentation/widgets/map_floating_controls.dart';

import '../../support/fakes.dart';

void main() {
  testWidgets('layer changes apply immediately and reload the viewport',
      (tester) async {
    final client = FakeApiClient();
    const emptyPage = {'items': <Object>[], 'next_cursor': null, 'limit': 100};
    client.setHandler('GET', 'cats', (_) => emptyPage);
    client.setHandler('GET', 'places', (_) => emptyPage);
    var lostPetReads = 0;
    client.setHandler('GET', 'lost-pets/map', (_) {
      lostPetReads++;
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
      mushukistanApiProvider.overrideWithValue(MushukistanApi(client: client)),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: MapScreen()),
    ));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(lostPetReads, 1);
    expect(find.byTooltip('Center on user'), findsOneWidget);
    expect(
        tester
            .widget<MapLocationControl>(find.byType(MapLocationControl))
            .active,
        isFalse);
    expect(find.byKey(const ValueKey('marker:lostPets:pet-1')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('map-layers-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('layer:lostPets')));
    await tester.pump();
    expect(find.byTooltip('Filters · 5/6'), findsOneWidget);
    expect(find.byKey(const ValueKey('marker:lostPets:pet-1')), findsNothing);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(lostPetReads, 1);

    await tester.tap(find.byKey(const ValueKey('layer:lostPets')));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(lostPetReads, 2);
    expect(find.byKey(const ValueKey('marker:lostPets:pet-1')), findsOneWidget);

    await tester.tap(find.text('Hide all'));
    await tester.pump();
    expect(find.byTooltip('Filters · 0/6'), findsOneWidget);
    expect(find.byKey(const ValueKey('marker:lostPets:pet-1')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('layer:vets')));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    final placeRequests = client.calls.where((call) =>
        call.path == 'places' &&
        (call.queryParameters?['category'] as List<dynamic>?)
                ?.contains('veterinary') ==
            true);
    expect(placeRequests, isNotEmpty);
    expect(lostPetReads, 2);
  });

  testWidgets('refresh failure keeps the last marker set and offers retry',
      (tester) async {
    final client = FakeApiClient();
    const emptyPage = {'items': <Object>[], 'next_cursor': null, 'limit': 100};
    client.setHandler('GET', 'cats', (_) => emptyPage);
    client.setHandler('GET', 'places', (_) => emptyPage);
    var reads = 0;
    client.setHandler('GET', 'lost-pets/map', (_) {
      reads++;
      if (reads > 1) throw StateError('offline');
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
      mushukistanApiProvider.overrideWithValue(MushukistanApi(client: client)),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: MapScreen()),
    ));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('map-layers-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Refresh'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.byKey(const ValueKey('marker:lostPets:pet-1')), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('Lost Pet preview identifies the marker and offers the post',
      (tester) async {
    final client = FakeApiClient();
    const emptyPage = {'items': <Object>[], 'next_cursor': null, 'limit': 100};
    client.setHandler('GET', 'cats', (_) => emptyPage);
    client.setHandler('GET', 'places', (_) => emptyPage);
    client.setHandler(
        'GET',
        'lost-pets/map',
        (_) => {
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
            });
    final container = ProviderContainer(overrides: [
      mushukistanApiProvider.overrideWithValue(MushukistanApi(client: client)),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: MapScreen()),
    ));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('marker:lostPets:pet-1')));
    await tester.pumpAndSettle();
    expect(
        find.byWidgetPredicate((widget) =>
            widget is Semantics && widget.properties.selected == true),
        findsOneWidget);
    expect(find.text('Mittens'), findsOneWidget);
    expect(find.textContaining('2026-09-28'), findsOneWidget);
    expect(find.text('Open post'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(
        find.byWidgetPredicate((widget) =>
            widget is Semantics && widget.properties.selected == true),
        findsNothing);
  });

  testWidgets('category cluster shows count and expands to individual markers',
      (tester) async {
    final client = FakeApiClient();
    const emptyPage = {'items': <Object>[], 'next_cursor': null, 'limit': 100};
    client.setHandler('GET', 'cats', (_) => emptyPage);
    client.setHandler('GET', 'places', (_) => emptyPage);
    client.setHandler(
        'GET',
        'lost-pets/map',
        (_) => {
              'items': [
                for (final id in ['pet-1', 'pet-2'])
                  {
                    'id': id,
                    'pet_name': id,
                    'last_seen_location': {
                      'latitude': 41.3,
                      'longitude': 69.25
                    },
                    'is_resolved': false,
                    'created_at': '2026-09-28T09:00:00Z',
                  }
              ],
              'next_cursor': null,
              'limit': 100,
            });
    final container = ProviderContainer(overrides: [
      mushukistanApiProvider.overrideWithValue(MushukistanApi(client: client)),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: MapScreen()),
    ));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.byTooltip('Lost pets: 2'), findsOneWidget);
    await tester.tap(find.byTooltip('Lost pets: 2'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byTooltip('Lost pets: 2'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const ValueKey('marker:lostPets:pet-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('marker:lostPets:pet-2')), findsOneWidget);
  });

  testWidgets('layer sheet fits phone and web viewports', (tester) async {
    final client = FakeApiClient();
    const emptyPage = {'items': <Object>[], 'next_cursor': null, 'limit': 100};
    client.setHandler('GET', 'cats', (_) => emptyPage);
    client.setHandler('GET', 'places', (_) => emptyPage);
    client.setHandler('GET', 'lost-pets/map', (_) => emptyPage);
    final container = ProviderContainer(overrides: [
      mushukistanApiProvider.overrideWithValue(MushukistanApi(client: client)),
    ]);
    addTearDown(container.dispose);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;

    for (final size in [
      const Size(320, 700),
      const Size(390, 844),
      const Size(430, 932),
      const Size(600, 900),
      const Size(1440, 900),
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Builder(builder: (context) {
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(size.width == 320 ? 2 : 1),
              ),
              child: const MapScreen(),
            );
          }),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.byKey(const ValueKey('map-layers-button')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
          tester.getSize(find.byKey(const ValueKey('map-layer-sheet'))).width,
          lessThanOrEqualTo(560));
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
    }
  });
}
