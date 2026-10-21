import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';
import 'package:mushukistan_frontend/features/map/presentation/screens/map_screen.dart';

import '../../support/fakes.dart';

const _focusRing = ValueKey('focus-needs-help-marker');

Future<void> _pumpMap(WidgetTester tester, Widget map) async {
  final apiClient = FakeApiClient();
  final emptyPage = {'items': <Object>[], 'next_cursor': null, 'limit': 100};
  apiClient.setHandler('GET', 'cats', (_) => emptyPage);
  apiClient.setHandler('GET', 'places', (_) => emptyPage);
  apiClient.setHandler('GET', 'lost-pets/map', (_) => emptyPage);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      mushukistanApiProvider
          .overrideWithValue(MushukistanApi(client: apiClient)),
    ],
    child: MaterialApp(home: map),
  ));
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump();
}

void main() {
  testWidgets('needs-help focus rings the exact coordinates', (tester) async {
    await _pumpMap(
      tester,
      const MapScreen(
        focusLocation: GeoPoint(latitude: 41.3111, longitude: 69.2797),
        focusNeedsHelp: true,
      ),
    );
    expect(find.byKey(_focusRing), findsOneWidget);
    final camera = MapCamera.of(tester.element(find.byKey(_focusRing)));
    expect(camera.center.latitude, moreOrLessEquals(41.3111, epsilon: 1e-6));
    expect(camera.center.longitude, moreOrLessEquals(69.2797, epsilon: 1e-6));
    expect(camera.zoom, 16);
  });

  testWidgets('no ring without the focus flag or outside the Map area',
      (tester) async {
    await _pumpMap(
      tester,
      const MapScreen(
        focusLocation: GeoPoint(latitude: 41.3111, longitude: 69.2797),
      ),
    );
    expect(find.byKey(_focusRing), findsNothing);

    await _pumpMap(
      tester,
      const MapScreen(
        key: ValueKey('outside'),
        focusLocation: GeoPoint(latitude: 39.65, longitude: 66.96),
        focusNeedsHelp: true,
      ),
    );
    expect(find.byKey(_focusRing), findsNothing);
  });

  testWidgets('an open Map recenters on a new focus location', (tester) async {
    await _pumpMap(
      tester,
      const MapScreen(
        focusLocation: GeoPoint(latitude: 41.30, longitude: 69.25),
        focusNeedsHelp: true,
      ),
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        mushukistanApiProvider.overrideWithValue(MushukistanApi(
            client: FakeApiClient()
              ..setHandler('GET', 'cats',
                  (_) => {'items': <Object>[], 'next_cursor': null})
              ..setHandler('GET', 'places',
                  (_) => {'items': <Object>[], 'next_cursor': null})
              ..setHandler('GET', 'lost-pets/map',
                  (_) => {'items': <Object>[], 'next_cursor': null}))),
      ],
      child: const MaterialApp(
        home: MapScreen(
          focusLocation: GeoPoint(latitude: 41.35, longitude: 69.33),
          focusNeedsHelp: true,
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    final camera = MapCamera.of(tester.element(find.byKey(_focusRing)));
    expect(camera.center.latitude, moreOrLessEquals(41.35, epsilon: 1e-4));
    expect(camera.center.longitude, moreOrLessEquals(69.33, epsilon: 1e-4));
  });
}
