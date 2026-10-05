import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';
import 'package:mushukistan_frontend/features/map/application/map_places_cache.dart';
import 'package:mushukistan_frontend/features/map/presentation/screens/map_screen.dart';
import 'package:mushukistan_frontend/features/map/presentation/widgets/map_clustered_marker_layer.dart';

import '../../support/fakes.dart';

class _StoredPlaces implements MapPlacesStorage {
  _StoredPlaces(this.encoded);
  String encoded;

  @override
  Future<String?> read(String key) async => encoded;

  @override
  Future<void> write(String key, String value) async {
    encoded = value;
  }
}

Map<String, Object?> _place(int index, {double? latitude, double? longitude}) =>
    {
      'id': 'p$index',
      'name': 'Place $index',
      'category': 'pet_shop',
      'categories': ['pet_shop'],
      'location': {
        'latitude': latitude ?? 41.25 + (index ~/ 16) * 0.006,
        'longitude': longitude ?? 69.17 + (index % 16) * 0.009,
      },
      'source': 'manual',
    };

MapPlacesController _controller(FakeApiClient client, List<Object?> places) {
  final stored = _StoredPlaces(jsonEncode({
    'schema': 1,
    'fetched_at': DateTime.now().toUtc().toIso8601String(),
    'items': places,
  }));
  return MapPlacesController(
    api: MushukistanApi(client: client),
    storage: stored,
    cacheKey: 'performance-test',
  );
}

void _emptyDynamicResponses(FakeApiClient client) {
  const empty = {'items': <Object>[], 'next_cursor': null, 'limit': 100};
  client.setHandler('GET', 'cats', (_) => empty);
  client.setHandler('GET', 'lost-pets/map', (_) => empty);
}

void main() {
  testWidgets('cached pin renders before any viewport request settles',
      (tester) async {
    final client = FakeApiClient();
    _emptyDynamicResponses(client);
    final controller = _controller(client, [
      _place(0, latitude: 41.2995, longitude: 69.2401),
    ]);
    final container = ProviderContainer(overrides: [
      mushukistanApiProvider.overrideWithValue(MushukistanApi(client: client)),
      mapPlacesControllerProvider.overrideWithValue(controller),
    ]);
    addTearDown(container.dispose);
    addTearDown(controller.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: MapScreen()),
    ));
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byKey(const ValueKey('marker:petShop:p0')), findsOneWidget);
    expect(client.calls, isEmpty);
  });

  testWidgets('pan waits for debounce and fetches only dynamic content',
      (tester) async {
    final client = FakeApiClient();
    _emptyDynamicResponses(client);
    final controller = _controller(client, [
      _place(0, latitude: 41.2995, longitude: 69.2401),
    ]);
    final container = ProviderContainer(overrides: [
      mushukistanApiProvider.overrideWithValue(MushukistanApi(client: client)),
      mapPlacesControllerProvider.overrideWithValue(controller),
    ]);
    addTearDown(container.dispose);
    addTearDown(controller.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: MapScreen()),
    ));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(client.calls, hasLength(2));
    await tester.drag(find.byType(FlutterMap), const Offset(100, 0));
    await tester.pump(const Duration(milliseconds: 100));
    expect(client.calls, hasLength(2));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(client.calls, hasLength(4));
    expect(client.calls.where((call) => call.path == 'places'), isEmpty);
  });

  testWidgets(
      '256 cached places need no API call and keep projection on state change',
      (tester) async {
    final client = FakeApiClient();
    _emptyDynamicResponses(client);
    final controller =
        _controller(client, [for (var i = 0; i < 256; i++) _place(i)]);
    final container = ProviderContainer(overrides: [
      mushukistanApiProvider.overrideWithValue(MushukistanApi(client: client)),
      mapPlacesControllerProvider.overrideWithValue(controller),
    ]);
    addTearDown(container.dispose);
    addTearDown(controller.dispose);
    MapClusteredMarkerLayer.debugRecomputeByLayer.clear();
    MapScreen.debugBuildCount = 0;

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: MapScreen()),
    ));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    final layer = tester
        .widget<MarkerLayer>(find.byKey(const ValueKey('place-marker-layer')));
    expect(layer.markers.length, greaterThan(0));
    expect(layer.markers.length, lessThan(256));
    expect(client.calls.where((call) => call.path == 'places'), isEmpty);
    final recomputes =
        MapClusteredMarkerLayer.debugRecomputeByLayer['place-marker-layer'];
    final builds = MapScreen.debugBuildCount;
    final tileLayer = tester.widget<TileLayer>(find.byType(TileLayer));

    container.read(resolvedLostPetIdsProvider.notifier).state = {'not-visible'};
    await tester.pump();
    expect(MapScreen.debugBuildCount, builds + 1);
    expect(MapClusteredMarkerLayer.debugRecomputeByLayer['place-marker-layer'],
        recomputes);
    expect(
        identical(tester.widget<TileLayer>(find.byType(TileLayer)), tileLayer),
        isTrue);

    final dynamicReadsBefore = client.calls.length;
    final buildsBeforeRefresh = MapScreen.debugBuildCount;
    container.read(postMutationRevisionProvider.notifier).state++;
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(client.calls.length, dynamicReadsBefore + 2);
    expect(client.calls.where((call) => call.path == 'places'), isEmpty);
    expect(MapScreen.debugBuildCount, buildsBeforeRefresh + 1);
    expect(MapClusteredMarkerLayer.debugRecomputeByLayer['place-marker-layer'],
        recomputes);
  });

  testWidgets('selection and place filter do not refetch or rebuild all pins',
      (tester) async {
    final client = FakeApiClient();
    _emptyDynamicResponses(client);
    client.setHandler('GET', 'places/p0',
        (_) => _place(0, latitude: 41.2995, longitude: 69.2401));
    final controller = _controller(client, [
      _place(0, latitude: 41.2995, longitude: 69.2401),
    ]);
    final container = ProviderContainer(overrides: [
      mushukistanApiProvider.overrideWithValue(MushukistanApi(client: client)),
      mapPlacesControllerProvider.overrideWithValue(controller),
    ]);
    addTearDown(container.dispose);
    addTearDown(controller.dispose);
    MapClusteredMarkerLayer.debugRecomputeByLayer.clear();
    MapScreen.debugBuildCount = 0;

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: MapScreen()),
    ));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    final builds = MapScreen.debugBuildCount;
    final recomputes =
        MapClusteredMarkerLayer.debugRecomputeByLayer['place-marker-layer'];
    await tester.tap(find.byKey(const ValueKey('marker:petShop:p0')));
    await tester.pumpAndSettle();
    expect(MapScreen.debugBuildCount, builds);
    expect(MapClusteredMarkerLayer.debugRecomputeByLayer['place-marker-layer'],
        recomputes);
    expect(find.text('Place 0'), findsOneWidget);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('map-layers-button')));
    await tester.pumpAndSettle();
    final readsBefore =
        client.calls.where((call) => call.path == 'places').length;
    final allReadsBefore = client.calls.length;
    final dynamicRecomputes =
        MapClusteredMarkerLayer.debugRecomputeByLayer['dynamic-marker-layer'];
    await tester.tap(find.byKey(const ValueKey('layer:shops')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(client.calls.where((call) => call.path == 'places').length,
        readsBefore);
    expect(client.calls.length, allReadsBefore);
    expect(
        MapClusteredMarkerLayer.debugRecomputeByLayer['dynamic-marker-layer'],
        dynamicRecomputes);
    final placeLayer = tester
        .widget<MarkerLayer>(find.byKey(const ValueKey('place-marker-layer')));
    expect(placeLayer.markers, isEmpty);
  });
}
