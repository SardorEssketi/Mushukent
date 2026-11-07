// EMU-105: each place marker is named after its place ("Elvet, veterinary
// clinic"), not only its category; clusters keep category and count.
// This checks the Flutter semantics tree; spoken screen-reader navigation of
// the map needs device QA.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/core/localization/language_controller.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';
import 'package:mushukistan_frontend/features/map/application/map_places_cache.dart';
import 'package:mushukistan_frontend/features/map/presentation/screens/map_screen.dart';
import 'package:mushukistan_frontend/features/map/presentation/widgets/map_clustered_marker_layer.dart';
import 'package:mushukistan_frontend/features/map/presentation/widgets/map_marker_visual.dart';

import '../../support/fakes.dart';

class _StoredPlaces implements MapPlacesStorage {
  _StoredPlaces(this.encoded);
  String encoded;

  @override
  Future<String?> read(String key) async => encoded;

  @override
  Future<void> write(String key, String value) async => encoded = value;
}

Map<String, Object?> _place(
  String id,
  String name,
  String category,
  double latitude,
  double longitude,
) =>
    {
      'id': id,
      'name': name,
      'category': category,
      'categories': [category],
      'location': {'latitude': latitude, 'longitude': longitude},
      'source': 'manual',
    };

/// Inside the start viewport, far enough apart to stay individual markers.
final _spread = [
  _place('v1', 'Elvet', 'veterinary', 41.2995, 69.2401),
  _place('v2', 'Synthetic Vet Two', 'veterinary', 41.2995, 69.2601),
  _place('ph1', 'Synthetic Pharmacy', 'veterinary_pharmacy', 41.2980, 69.2360),
  _place('s1', 'Synthetic Pet Shop', 'pet_shop', 41.3005, 69.2370),
];

Future<ProviderContainer> _mount(
  WidgetTester tester,
  List<Map<String, Object?>> places, {
  AppLanguage language = AppLanguage.english,
}) async {
  final client = FakeApiClient();
  const empty = {'items': <Object>[], 'next_cursor': null, 'limit': 100};
  client.setHandler('GET', 'cats', (_) => empty);
  client.setHandler('GET', 'lost-pets/map', (_) => empty);
  for (final place in places) {
    client.setHandler('GET', 'places/${place['id']}', (_) => place);
  }
  final controller = MapPlacesController(
    api: MushukistanApi(client: client),
    storage: _StoredPlaces(jsonEncode({
      'schema': 1,
      'fetched_at': DateTime.now().toUtc().toIso8601String(),
      'items': places,
    })),
    cacheKey: 'marker-names-test',
  );
  final container = ProviderContainer(overrides: [
    mushukistanApiProvider.overrideWithValue(MushukistanApi(client: client)),
    mapPlacesControllerProvider.overrideWithValue(controller),
    appLanguageProvider.overrideWith((ref) => language),
  ]);
  addTearDown(container.dispose);
  addTearDown(controller.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: MapScreen()),
  ));
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump();
  return container;
}

SemanticsData _node(WidgetTester tester, String label) =>
    tester.getSemantics(find.bySemanticsLabel(label)).getSemanticsData();

void main() {
  testWidgets('each place marker is named by its place and type',
      (tester) async {
    final handle = tester.ensureSemantics();
    await _mount(tester, _spread);
    for (final label in [
      'Elvet, veterinary clinic',
      'Synthetic Vet Two, veterinary clinic',
      'Synthetic Pharmacy, vet pharmacy',
      'Synthetic Pet Shop, pet shop',
    ]) {
      final node = _node(tester, label);
      expect(node.hasFlag(SemanticsFlag.isButton), isTrue, reason: label);
      expect(node.tooltip, isEmpty, reason: 'no duplicate announcement');
    }
    // No two individual markers share a name; no category-only names.
    expect(find.bySemanticsLabel(RegExp(r'^(Vets|Vet pharmacies|Shops)$')),
        findsNothing);
    handle.dispose();
  });

  testWidgets('tapping a named marker selects it and opens its preview',
      (tester) async {
    final handle = tester.ensureSemantics();
    await _mount(tester, _spread);
    await tester.tap(find.byKey(const ValueKey('marker:veterinary:v1')));
    await tester.pumpAndSettle();
    final marker = tester.widget<MapMarkerVisual>(find.descendant(
        of: find.byKey(const ValueKey('marker:veterinary:v1')),
        matching: find.byType(MapMarkerVisual)));
    expect(marker.selected, isTrue);
    expect(marker.label, 'Elvet, veterinary clinic');
    expect(find.text('Elvet'), findsWidgets, reason: 'preview opened');
    handle.dispose();
  });

  testWidgets('a cluster keeps category and count; expanded pins are named',
      (tester) async {
    final handle = tester.ensureSemantics();
    final close = [
      for (var i = 0; i < 3; i++)
        _place('c$i', 'Clinic $i', 'veterinary', 41.2995 + i * 0.0015,
            69.2401 + i * 0.0015),
    ];
    await _mount(tester, close);
    expect(find.bySemanticsLabel('Vets: 3'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Clinic \d, veterinary clinic$')),
        findsNothing);
    // Expanding (each tap zooms in) until every clinic is its own pin.
    final clusters = find.bySemanticsLabel(RegExp(r'^Vets: \d+$'));
    for (var i = 0; i < 6 && clusters.evaluate().isNotEmpty; i++) {
      await tester.tap(clusters.first);
      await tester.pumpAndSettle();
    }
    expect(clusters, findsNothing);
    for (var i = 0; i < 3; i++) {
      expect(find.bySemanticsLabel('Clinic $i, veterinary clinic'),
          findsOneWidget);
    }
    handle.dispose();
  });

  testWidgets('types are localized; proper names are not', (tester) async {
    final handle = tester.ensureSemantics();
    await _mount(tester, _spread, language: AppLanguage.russian);
    expect(find.bySemanticsLabel('Elvet, ветклиника'), findsOneWidget);
    expect(
        find.bySemanticsLabel('Synthetic Pharmacy, ветаптека'), findsOneWidget);
    expect(find.bySemanticsLabel('Synthetic Pet Shop, зоомагазин'),
        findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await _mount(tester, _spread, language: AppLanguage.uzbek);
    expect(
        find.bySemanticsLabel('Elvet, veterinariya klinikasi'), findsOneWidget);
    expect(
        find.bySemanticsLabel('Synthetic Pet Shop, zoodo‘kon'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('many places: names do not add rebuilds or recomputation',
      (tester) async {
    final many = [
      for (var i = 0; i < 256; i++)
        _place('p$i', 'Shop $i', 'pet_shop', 41.25 + (i ~/ 16) * 0.006,
            69.17 + (i % 16) * 0.009),
    ];
    MapClusteredMarkerLayer.debugRecomputeByLayer.clear();
    MapScreen.debugBuildCount = 0;
    await _mount(tester, many);
    final builds = MapScreen.debugBuildCount;
    final recomputes =
        MapClusteredMarkerLayer.debugRecomputeByLayer['place-marker-layer'];
    await tester.pump(const Duration(milliseconds: 500));
    expect(MapScreen.debugBuildCount, builds);
    expect(MapClusteredMarkerLayer.debugRecomputeByLayer['place-marker-layer'],
        recomputes);
  });
}
