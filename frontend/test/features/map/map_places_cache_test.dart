import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';
import 'package:mushukistan_frontend/features/map/application/map_places_cache.dart';

import '../../support/fakes.dart';

class _MemoryStorage implements MapPlacesStorage {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

Map<String, Object?> _place(String id, String name,
        {String category = 'pet_shop'}) =>
    {
      'id': id,
      'name': name,
      'category': category,
      'categories': [category],
      'location': {'latitude': 41.3, 'longitude': 69.25},
      'source': 'manual',
    };

Map<String, Object?> _page(List<Map<String, Object?>> places) => {
      'items': places,
      'next_cursor': null,
      'limit': 200,
    };

void main() {
  test('cache miss fetches all categories and a fresh cache avoids requests',
      () async {
    final storage = _MemoryStorage();
    final client = FakeApiClient();
    client.setHandler('GET', 'places', (call) {
      final category = (call.queryParameters!['category'] as List).single;
      return _page(category == 'pet_shop' || category == 'veterinary_pharmacy'
          ? [_place('p1', 'First')]
          : []);
    });
    final now = DateTime.utc(2026, 10, 4);
    final first = MapPlacesController(
      api: MushukistanApi(client: client),
      storage: storage,
      cacheKey: 'test-places',
      clock: () => now,
    );
    await first.open();
    expect(client.calls, hasLength(4));
    expect(first.places.map((place) => place.id), ['p1']);
    first.dispose();

    final secondClient = FakeApiClient();
    final second = MapPlacesController(
      api: MushukistanApi(client: secondClient),
      storage: storage,
      cacheKey: 'test-places',
      clock: () => now.add(const Duration(hours: 1)),
    );
    await second.open();
    expect(second.places.single.name, 'First');
    expect(secondClient.calls, isEmpty);
    second.dispose();
  });

  test('stale cached pins appear before background refresh completes',
      () async {
    final storage = _MemoryStorage();
    storage.values['test-places'] = jsonEncode({
      'schema': 1,
      'fetched_at': DateTime.utc(2026, 10, 3).toIso8601String(),
      'items': [_place('p1', 'Old')],
    });
    final pending = Completer<Object?>();
    final client = FakeApiClient();
    client.setHandler('GET', 'places', (call) {
      final category = (call.queryParameters!['category'] as List).single;
      return category == 'pet_shop' ? pending.future : _page([]);
    });
    final controller = MapPlacesController(
      api: MushukistanApi(client: client),
      storage: storage,
      cacheKey: 'test-places',
      clock: () => DateTime.utc(2026, 10, 4),
    );
    final opening = controller.open();
    await Future<void>.delayed(Duration.zero);
    expect(controller.places.single.name, 'Old');
    expect(client.calls, hasLength(4));
    pending.complete(_page([_place('p1', 'New')]));
    await opening;
    expect(controller.places.single.name, 'New');
    controller.dispose();
  });

  test('failed refresh leaves stale cached pins available', () async {
    final storage = _MemoryStorage();
    storage.values['test-places'] = jsonEncode({
      'schema': 1,
      'fetched_at': DateTime.utc(2026, 10, 3).toIso8601String(),
      'items': [_place('p1', 'Offline pin')],
    });
    final client = FakeApiClient();
    client.setHandler('GET', 'places', (call) {
      if ((call.queryParameters!['category'] as List).single == 'pet_shop') {
        throw StateError('offline');
      }
      return _page([]);
    });
    final controller = MapPlacesController(
      api: MushukistanApi(client: client),
      storage: storage,
      cacheKey: 'test-places',
      clock: () => DateTime.utc(2026, 10, 4),
    );
    await expectLater(controller.open(), throwsStateError);
    expect(controller.places.single.name, 'Offline pin');
    controller.dispose();
  });

  test('a future cache timestamp cannot suppress refresh forever', () async {
    final storage = _MemoryStorage();
    storage.values['test-places'] = jsonEncode({
      'schema': 1,
      'fetched_at': DateTime.utc(2030, 1, 1).toIso8601String(),
      'items': [_place('p1', 'Old')],
    });
    final client = FakeApiClient();
    client.setHandler('GET', 'places', (call) {
      final category = (call.queryParameters!['category'] as List).single;
      return _page(category == 'pet_shop' ? [_place('p1', 'Current')] : []);
    });
    final controller = MapPlacesController(
      api: MushukistanApi(client: client),
      storage: storage,
      cacheKey: 'test-places',
      clock: () => DateTime.utc(2026, 10, 4),
    );
    await controller.open();
    expect(client.calls, hasLength(4));
    expect(controller.places.single.name, 'Current');
    controller.dispose();
  });

  test('unchanged refresh does not notify map listeners', () async {
    final storage = _MemoryStorage();
    final client = FakeApiClient();
    client.setHandler('GET', 'places', (call) {
      final category = (call.queryParameters!['category'] as List).single;
      return _page(category == 'pet_shop' ? [_place('p1', 'Same')] : []);
    });
    final controller = MapPlacesController(
      api: MushukistanApi(client: client),
      storage: storage,
      cacheKey: 'test-places',
    );
    var notifications = 0;
    controller.addListener(() => notifications++);
    await controller.open();
    await controller.refresh();
    expect(notifications, 1);
    controller.dispose();
  });

  test('a capped category response is split rather than silently truncated',
      () async {
    final client = FakeApiClient();
    var petShopCalls = 0;
    client.setHandler('GET', 'places', (call) {
      final category = (call.queryParameters!['category'] as List).single;
      if (category != 'pet_shop') return _page([]);
      petShopCalls++;
      if (petShopCalls == 1) {
        return _page([for (var i = 0; i < 200; i++) _place('p$i', 'P$i')]);
      }
      final start = petShopCalls == 2 ? 0 : 51 + (petShopCalls - 3) * 50;
      final count = petShopCalls == 2 ? 51 : 50;
      return _page([
        for (var i = 0; i < count; i++) _place('p${start + i}', 'P${start + i}')
      ]);
    });
    final controller = MapPlacesController(
      api: MushukistanApi(client: client),
      storage: _MemoryStorage(),
      cacheKey: 'test-places',
    );
    await controller.open();
    expect(petShopCalls, 5);
    expect(controller.places, hasLength(201));
    controller.dispose();
  });
}
