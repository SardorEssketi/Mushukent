import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/core/location/location_service.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';
import 'package:mushukistan_frontend/features/map/application/map_viewport.dart';
import 'package:mushukistan_frontend/features/map/presentation/screens/map_screen.dart';

import '../../support/fakes.dart';

const _lostRing = ValueKey('focus-lost-pet-marker');
const _helpRing = ValueKey('focus-needs-help-marker');

Map<String, Object?> _lostPetsPage(double lat, double lon) => {
      'items': [
        {
          'id': 'pet-1',
          'pet_name': 'Milo',
          'last_seen_location': {'latitude': lat, 'longitude': lon},
          'is_resolved': false,
          'created_at': '2026-09-28T09:00:00Z',
        }
      ],
      'next_cursor': null,
      'limit': 100,
    };

FakeApiClient _client({Map<String, Object?>? lostPets}) {
  final empty = {'items': <Object>[], 'next_cursor': null, 'limit': 100};
  return FakeApiClient()
    ..setHandler('GET', 'cats', (_) => empty)
    ..setHandler('GET', 'places', (_) => empty)
    ..setHandler('GET', 'lost-pets/map', (_) => lostPets ?? empty);
}

Future<void> _pumpMap(WidgetTester tester, Widget map,
    {FakeApiClient? client}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      mushukistanApiProvider
          .overrideWithValue(MushukistanApi(client: client ?? _client())),
    ],
    child: MaterialApp(home: map),
  ));
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump();
}

MapCamera _camera(WidgetTester tester) => MapCamera.of(
    tester.element(find.byKey(const ValueKey('fixed-marker-layer'))));

void main() {
  group('mapSupportedLocation', () {
    final south = tashkentMapBounds.south;
    final north = tashkentMapBounds.north;
    final west = tashkentMapBounds.west;
    final east = tashkentMapBounds.east;

    test('accepts points inside the Map area, including its edges', () {
      for (final point in [
        const GeoPoint(latitude: 41.3111, longitude: 69.2797),
        GeoPoint(latitude: south, longitude: west),
        GeoPoint(latitude: north, longitude: east),
        GeoPoint(latitude: south, longitude: east),
        GeoPoint(latitude: north, longitude: west),
      ]) {
        expect(mapSupportedLocation(point), same(point),
            reason: '${point.latitude},${point.longitude}');
      }
    });

    test('rejects missing, malformed, non-finite and outside points', () {
      expect(mapSupportedLocation(null), isNull);
      for (final point in [
        // Malformed API strings parse as 0,0.
        GeoPoint.fromJson({'latitude': 'abc', 'longitude': 'x'}),
        const GeoPoint(latitude: 0, longitude: 0),
        const GeoPoint(latitude: double.nan, longitude: 69.28),
        const GeoPoint(latitude: 41.31, longitude: double.infinity),
        const GeoPoint(latitude: 39.65, longitude: 66.96), // Samarkand
        GeoPoint(latitude: south - 1e-6, longitude: 69.28),
        GeoPoint(latitude: north + 1e-6, longitude: 69.28),
        GeoPoint(latitude: 41.31, longitude: west - 1e-6),
        GeoPoint(latitude: 41.31, longitude: east + 1e-6),
        const GeoPoint(latitude: 69.28, longitude: 41.31), // swapped
      ]) {
        expect(mapSupportedLocation(point), isNull,
            reason: '${point.latitude},${point.longitude}');
      }
    });
  });

  group('Map focus', () {
    testWidgets('a supported Lost Pet focus centers and rings the pet',
        (tester) async {
      await _pumpMap(
        tester,
        const MapScreen(
          focusLocation: GeoPoint(latitude: 41.3, longitude: 69.25),
          focusLostPetId: 'pet-1',
        ),
        client: _client(lostPets: _lostPetsPage(41.3, 69.25)),
      );
      expect(find.byKey(_lostRing), findsOneWidget);
      expect(_camera(tester).center.latitude, moreOrLessEquals(41.3));
      expect(_camera(tester).center.longitude, moreOrLessEquals(69.25));
      expect(_camera(tester).zoom, 16);
    });

    testWidgets('an unsupported focus is ignored instead of clamped',
        (tester) async {
      await _pumpMap(
        tester,
        const MapScreen(
          focusLocation: GeoPoint(latitude: 39.65, longitude: 66.96),
          focusLostPetId: 'pet-1',
          focusNeedsHelp: true,
        ),
        client: _client(lostPets: _lostPetsPage(39.65, 66.96)),
      );
      expect(find.byKey(_lostRing), findsNothing);
      expect(find.byKey(_helpRing), findsNothing);
      // The default city view, not a street-level view at the boundary.
      final camera = _camera(tester);
      expect(camera.zoom, 13.6);
      expect(camera.center.latitude,
          moreOrLessEquals(LocationService.fallbackLocation.latitude));
      expect(camera.center.longitude,
          moreOrLessEquals(LocationService.fallbackLocation.longitude));
    });

    testWidgets('non-finite coordinates are ignored', (tester) async {
      await _pumpMap(
        tester,
        const MapScreen(
          focusLocation: GeoPoint(latitude: double.nan, longitude: 69.25),
          focusNeedsHelp: true,
        ),
      );
      expect(find.byKey(_helpRing), findsNothing);
      expect(_camera(tester).zoom, 13.6);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an open Map moves to a new supported focus only',
        (tester) async {
      final client = _client();
      await _pumpMap(
        tester,
        const MapScreen(
          focusLocation: GeoPoint(latitude: 41.30, longitude: 69.25),
          focusNeedsHelp: true,
        ),
        client: client,
      );
      // An unsupported request leaves the camera where it was.
      await _pumpMap(
        tester,
        const MapScreen(
          focusLocation: GeoPoint(latitude: 39.65, longitude: 66.96),
          focusLostPetId: 'pet-1',
        ),
        client: client,
      );
      expect(_camera(tester).center.latitude, moreOrLessEquals(41.30));
      expect(_camera(tester).center.longitude, moreOrLessEquals(69.25));
      expect(find.byKey(_lostRing), findsNothing);

      // A supported one moves it.
      await _pumpMap(
        tester,
        const MapScreen(
          focusLocation: GeoPoint(latitude: 41.35, longitude: 69.33),
          focusNeedsHelp: true,
        ),
        client: client,
      );
      expect(_camera(tester).center.latitude,
          moreOrLessEquals(41.35, epsilon: 1e-4));
      expect(_camera(tester).center.longitude,
          moreOrLessEquals(69.33, epsilon: 1e-4));
      expect(find.byKey(_helpRing), findsOneWidget);
    });
  });
}
