import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

enum MapDensityTier { low, medium, high }

enum MapMarkerKind { observation, needsHelp, lostPet }

MapMarkerKind mapMarkerKindForPostKind(String? postKind) {
  return postKind == 'needs_help'
      ? MapMarkerKind.needsHelp
      : MapMarkerKind.observation;
}

IconData mapMarkerIconForKind(MapMarkerKind kind) {
  return switch (kind) {
    MapMarkerKind.observation => Icons.pets,
    MapMarkerKind.needsHelp => Icons.warning_amber,
    MapMarkerKind.lostPet => Icons.priority_high,
  };
}

MapDensityTier mapDensityTierForZoom(double zoom) {
  if (zoom < 14) {
    return MapDensityTier.low;
  }
  if (zoom < 16) {
    return MapDensityTier.medium;
  }
  return MapDensityTier.high;
}

double? mapClusterCellSizeForZoom(double zoom) {
  return switch (mapDensityTierForZoom(zoom)) {
    MapDensityTier.low => 96,
    MapDensityTier.medium => 64,
    MapDensityTier.high => null,
  };
}

class MapViewportQuery {
  const MapViewportQuery({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
    required this.zoom,
  });

  final double south;
  final double west;
  final double north;
  final double east;
  final double zoom;

  String get bbox => [west, south, east, north]
      .map((value) => value.toStringAsFixed(5))
      .join(',');

  MapDensityTier get densityTier => mapDensityTierForZoom(zoom);

  String requestKey(String filterKey) => '$bbox|$filterKey';

  factory MapViewportQuery.fromCamera(
    MapCamera camera, {
    required LatLngBounds allowedBounds,
  }) {
    return MapViewportQuery.fromBounds(
      camera.visibleBounds,
      allowedBounds: allowedBounds,
      zoom: camera.zoom,
    );
  }

  factory MapViewportQuery.fromBounds(
    LatLngBounds visibleBounds, {
    required LatLngBounds allowedBounds,
    required double zoom,
  }) {
    final south = _roundCoordinate(
      math.max(allowedBounds.south, visibleBounds.south),
    );
    final west = _roundCoordinate(
      math.max(allowedBounds.west, visibleBounds.west),
    );
    final north = _roundCoordinate(
      math.min(allowedBounds.north, visibleBounds.north),
    );
    final east = _roundCoordinate(
      math.min(allowedBounds.east, visibleBounds.east),
    );
    return MapViewportQuery(
      south: south,
      west: west,
      north: north,
      east: east,
      zoom: zoom,
    );
  }

  static double _roundCoordinate(double value) =>
      (value * 100000).roundToDouble() / 100000;
}

class ViewportRequestScheduler {
  ViewportRequestScheduler({
    required this.onSettled,
    this.onScheduled,
    this.debounce = const Duration(milliseconds: 350),
  });

  final Duration debounce;
  final void Function(MapViewportQuery query) onSettled;
  final VoidCallback? onScheduled;

  Timer? _timer;
  String? _pendingKey;
  String? _lastDispatchedKey;

  void schedule(
    MapViewportQuery query, {
    required String filterKey,
    bool force = false,
  }) {
    final key = query.requestKey(filterKey);
    if (!force && (key == _pendingKey || key == _lastDispatchedKey)) {
      return;
    }
    onScheduled?.call();
    _timer?.cancel();
    _pendingKey = key;
    _timer = Timer(debounce, () {
      _timer = null;
      _pendingKey = null;
      _lastDispatchedKey = key;
      onSettled(query);
    });
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}

class ViewportRequestGuard {
  int _generation = 0;

  void invalidate() => _generation++;

  int begin() => ++_generation;

  bool isCurrent(int generation) => generation == _generation;
}
