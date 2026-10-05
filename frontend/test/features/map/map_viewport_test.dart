import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:mushukistan_frontend/features/map/application/map_viewport.dart';

void main() {
  final allowedBounds = tashkentMapBounds;

  test('viewport bbox is clamped to the map bounds, including edges', () {
    final query = MapViewportQuery.fromBounds(
      LatLngBounds(
        const LatLng(41.100001, 68.900001),
        const LatLng(41.430001, 69.500001),
      ),
      allowedBounds: allowedBounds,
      zoom: 13.6,
    );

    expect(query.bbox, '69.05000,41.18000,69.47000,41.43000');
  });

  test('eastern V2 place points remain inside the map viewport', () {
    expect(allowedBounds.contains(const LatLng(41.402798, 69.450821)), isTrue);
  });

  test('zoom density tiers match marker scale', () {
    expect(mapClusterCellSizeForZoom(13.6), 96);
    expect(mapClusterCellSizeForZoom(15), 64);
    expect(mapClusterCellSizeForZoom(16), isNull);
  });

  test('needs-help and normal observation markers stay distinct', () {
    expect(
      mapMarkerKindForPostKind('observation'),
      MapMarkerKind.observation,
    );
    expect(
      mapMarkerKindForPostKind('needs_help'),
      MapMarkerKind.needsHelp,
    );
    expect(mapMarkerKindForPostKind(null), MapMarkerKind.observation);
    expect(
      mapMarkerIconForKind(MapMarkerKind.needsHelp),
      isNot(mapMarkerIconForKind(MapMarkerKind.observation)),
    );
  });

  test('lost-pet marker stays distinct from observation marker', () {
    expect(
      mapMarkerIconForKind(MapMarkerKind.lostPet),
      isNot(mapMarkerIconForKind(MapMarkerKind.observation)),
    );
  });

  test('scheduler debounces and suppresses duplicate viewport requests',
      () async {
    final requests = <MapViewportQuery>[];
    final scheduler = ViewportRequestScheduler(
      debounce: const Duration(milliseconds: 20),
      onSettled: requests.add,
    );
    final query = MapViewportQuery.fromBounds(
      LatLngBounds(const LatLng(41.25, 69.20), const LatLng(41.35, 69.30)),
      allowedBounds: allowedBounds,
      zoom: 14,
    );

    scheduler.schedule(query, filterKey: 'observations');
    scheduler.schedule(query, filterKey: 'observations');
    await Future<void>.delayed(const Duration(milliseconds: 30));
    scheduler.schedule(query, filterKey: 'observations');
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(requests, hasLength(1));
    scheduler.dispose();
  });

  test('density tier does not change backend request identity', () {
    final lowZoom = MapViewportQuery.fromBounds(
      LatLngBounds(const LatLng(41.25, 69.20), const LatLng(41.35, 69.30)),
      allowedBounds: allowedBounds,
      zoom: 13.9,
    );
    final mediumZoom = MapViewportQuery.fromBounds(
      LatLngBounds(const LatLng(41.25, 69.20), const LatLng(41.35, 69.30)),
      allowedBounds: allowedBounds,
      zoom: 14,
    );

    expect(lowZoom.densityTier, isNot(mediumZoom.densityTier));
    expect(
      lowZoom.requestKey('observations'),
      mediumZoom.requestKey('observations'),
    );
  });

  test('new viewport invalidates an in-flight response during debounce',
      () async {
    final guard = ViewportRequestGuard();
    final updates = <String>[];
    int? firstRequestGeneration;
    MapViewportQuery? dispatchedQuery;
    final scheduler = ViewportRequestScheduler(
      debounce: const Duration(milliseconds: 20),
      onScheduled: guard.invalidate,
      onSettled: (query) {
        dispatchedQuery = query;
        final generation = guard.begin();
        firstRequestGeneration ??= generation;
      },
    );
    final firstQuery = MapViewportQuery.fromBounds(
      LatLngBounds(const LatLng(41.25, 69.20), const LatLng(41.35, 69.30)),
      allowedBounds: allowedBounds,
      zoom: 14,
    );
    final secondQuery = MapViewportQuery.fromBounds(
      LatLngBounds(const LatLng(41.26, 69.21), const LatLng(41.36, 69.31)),
      allowedBounds: allowedBounds,
      zoom: 14,
    );

    scheduler.schedule(firstQuery, filterKey: 'observations');
    await Future<void>.delayed(const Duration(milliseconds: 30));
    scheduler.schedule(secondQuery, filterKey: 'observations');

    if (guard.isCurrent(firstRequestGeneration!)) {
      updates.add('first');
    }

    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(updates, isEmpty);
    expect(dispatchedQuery, secondQuery);
    scheduler.dispose();
  });

  test('request guard rejects stale responses', () {
    final guard = ViewportRequestGuard();
    final first = guard.begin();
    final second = guard.begin();

    expect(guard.isCurrent(first), isFalse);
    expect(guard.isCurrent(second), isTrue);
  });

  test('dynamic responses deduplicate in-flight and recent identical bounds',
      () async {
    var now = DateTime.utc(2026, 10, 4);
    final cache = ViewportResponseCache<int>(clock: () => now);
    final completer = Completer<int>();
    var calls = 0;
    Future<int> fetch() {
      calls++;
      return completer.future;
    }

    final first = cache.get('same-bbox', fetch);
    final second = cache.get('same-bbox', fetch);
    expect(identical(first, second), isTrue);
    expect(calls, 1);
    completer.complete(42);
    expect(await first, 42);
    expect(await cache.get('same-bbox', () async => 99), 42);
    expect(calls, 1);

    now = now.add(const Duration(seconds: 16));
    expect(await cache.get('same-bbox', () async => ++calls), 2);
    expect(await cache.get('same-bbox', () async => ++calls, force: true), 3);
  });
}
