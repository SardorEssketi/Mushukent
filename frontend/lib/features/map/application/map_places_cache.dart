import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/mushukistan_api.dart';
import 'map_viewport.dart';

abstract class MapPlacesStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class PreferencesMapPlacesStorage implements MapPlacesStorage {
  PreferencesMapPlacesStorage([SharedPreferencesAsync? preferences])
      : _preferences = preferences;

  SharedPreferencesAsync? _preferences;
  SharedPreferencesAsync get _store =>
      _preferences ??= SharedPreferencesAsync();

  @override
  Future<String?> read(String key) => _store.getString(key);

  @override
  Future<void> write(String key, String value) async {
    await _store.setString(key, value);
  }
}

final mapPlacesControllerProvider = Provider<MapPlacesController>((ref) {
  final api = ref.watch(mushukistanApiProvider);
  final controller = MapPlacesController(
    api: api,
    storage: PreferencesMapPlacesStorage(),
    cacheKey: 'map_places_v1_${api.baseUri?.origin ?? 'local'}',
  );
  ref.onDispose(controller.dispose);
  return controller;
});

/// A small, versioned cache for public map pins. Full place details are fetched
/// from the API only when a marker is opened.
class MapPlacesController extends ChangeNotifier {
  MapPlacesController({
    required this.api,
    required this.storage,
    required this.cacheKey,
    this.maxAge = const Duration(hours: 6),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  static const categories = <String>[
    'pet_shop',
    'veterinary',
    'veterinary_pharmacy',
    'shelter',
  ];
  static const _pageLimit = 200;
  static const _schemaVersion = 1;
  static const _maxSplitDepth = 5;

  final MushukistanApi api;
  final MapPlacesStorage storage;
  final String cacheKey;
  final Duration maxAge;
  final DateTime Function() _clock;

  List<PlaceSummary> _places = const [];
  List<PlaceSummary> get places => _places;
  DateTime? _fetchedAt;
  Future<void>? _hydration;
  Future<void>? _refresh;
  String? _contentFingerprint;
  bool _disposed = false;

  Future<void> open() async {
    await (_hydration ??= _hydrate());
    final fetchedAt = _fetchedAt;
    final age = fetchedAt == null ? null : _clock().difference(fetchedAt);
    if (age == null || age.isNegative || age >= maxAge) {
      await refresh();
    }
  }

  Future<void> refresh() async {
    await (_hydration ??= _hydrate());
    await (_refresh ??= _fetchAndPublish().whenComplete(() {
      _refresh = null;
    }));
  }

  Future<void> _hydrate() async {
    try {
      final encoded = await storage.read(cacheKey);
      if (encoded == null) return;
      final envelope = jsonDecode(encoded) as Map<String, dynamic>;
      if (envelope['schema'] != _schemaVersion) return;
      final items = (envelope['items'] as List<dynamic>)
          .map((item) => PlaceSummary.fromJson(item))
          .toList(growable: false);
      _fetchedAt = DateTime.parse(envelope['fetched_at'] as String);
      _publish(items);
    } catch (_) {
      // Corrupt or unavailable local storage is a cache miss, not a map error.
    }
  }

  Future<void> _fetchAndPublish() async {
    final pages = await Future.wait([
      for (final category in categories)
        _fetchCategory(
          category,
          south: tashkentMapBounds.south,
          west: tashkentMapBounds.west,
          north: tashkentMapBounds.north,
          east: tashkentMapBounds.east,
          depth: 0,
        ),
    ]);
    final byId = <String, PlaceSummary>{};
    for (final page in pages) {
      for (final place in page) {
        byId[place.id] = place;
      }
    }
    final next = byId.values.toList(growable: false)
      ..sort((a, b) => a.id.compareTo(b.id));
    final fetchedAt = _clock().toUtc();
    _publish(next);
    _fetchedAt = fetchedAt;
    try {
      await storage.write(
          cacheKey,
          jsonEncode({
            'schema': _schemaVersion,
            'fetched_at': fetchedAt.toIso8601String(),
            'items': next.map(_toCacheJson).toList(growable: false),
          }));
    } catch (_) {
      // In-memory pins remain usable when local storage is unavailable.
    }
  }

  Future<List<PlaceSummary>> _fetchCategory(
    String category, {
    required double south,
    required double west,
    required double north,
    required double east,
    required int depth,
  }) async {
    final bbox = [west, south, east, north]
        .map((value) => value.toStringAsFixed(5))
        .join(',');
    final page = await api.listPlaces(
      categories: [category],
      bbox: bbox,
      limit: _pageLimit,
      mapOnly: true,
    );
    if (page.items.length < _pageLimit) return page.items;
    if (depth >= _maxSplitDepth) {
      throw StateError('Place map response remains capped after bbox splits.');
    }
    final midLat = (south + north) / 2;
    final midLon = (west + east) / 2;
    final quadrants = await Future.wait([
      _fetchCategory(category,
          south: south,
          west: west,
          north: midLat,
          east: midLon,
          depth: depth + 1),
      _fetchCategory(category,
          south: south,
          west: midLon,
          north: midLat,
          east: east,
          depth: depth + 1),
      _fetchCategory(category,
          south: midLat,
          west: west,
          north: north,
          east: midLon,
          depth: depth + 1),
      _fetchCategory(category,
          south: midLat,
          west: midLon,
          north: north,
          east: east,
          depth: depth + 1),
    ]);
    return [for (final items in quadrants) ...items];
  }

  void _publish(List<PlaceSummary> next) {
    if (_disposed) return;
    final fingerprint = jsonEncode(next.map(_toCacheJson).toList());
    if (fingerprint == _contentFingerprint) return;
    _contentFingerprint = fingerprint;
    _places = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

Map<String, Object?> _toCacheJson(PlaceSummary place) => {
      'id': place.id,
      'name': place.name,
      'category': place.category,
      'categories': place.categories,
      'location': place.location.toJson(),
      'source': place.source,
    };
