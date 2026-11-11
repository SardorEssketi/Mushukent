import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../application/map_viewport.dart';
import 'map_marker_visual.dart';

class MapMarkerSpec {
  const MapMarkerSpec({
    required this.id,
    required this.point,
    required this.child,
    this.width = 52,
    this.height = 52,
  });

  final String id;
  final LatLng point;
  final double width;
  final double height;
  final Widget child;
}

class MapMarkerGroup {
  const MapMarkerGroup({
    required this.specs,
    required this.kind,
    required this.label,
  });

  final List<MapMarkerSpec> specs;
  final MapMarkerVisualKind kind;
  final String label;
}

/// Keeps the expensive MarkerLayer projection cache across camera pans and
/// unrelated parent rebuilds. Clusters are recalculated only when the data
/// changes or the camera crosses a whole zoom level, so a pinch gesture (which
/// moves through fractional zooms every frame) does not reshuffle pins between
/// clusters and make them jitter.
class MapClusteredMarkerLayer extends StatefulWidget {
  const MapClusteredMarkerLayer({
    super.key,
    required this.groups,
    required this.layerKey,
    required this.onClusterTap,
    this.revision,
  });

  final List<MapMarkerGroup> groups;
  final String layerKey;
  final void Function(LatLng point) onClusterTap;

  /// When provided, an unchanged revision retains the existing marker widgets.
  final Object? revision;

  @visibleForTesting
  static int debugRecomputeCount = 0;
  @visibleForTesting
  static final debugRecomputeByLayer = <String, int>{};

  @override
  State<MapClusteredMarkerLayer> createState() =>
      _MapClusteredMarkerLayerState();
}

class _MapClusteredMarkerLayerState extends State<MapClusteredMarkerLayer> {
  double? _clusterZoom;
  MarkerLayer? _layer;

  @override
  void didUpdateWidget(MapClusteredMarkerLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.revision != null || oldWidget.revision != null) {
      if (widget.revision != oldWidget.revision) _layer = null;
    } else if (!identical(oldWidget.groups, widget.groups)) {
      _layer = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final clusterZoom = mapClusterZoomLevel(camera.zoom);
    if (_layer == null || _clusterZoom != clusterZoom) {
      assert(() {
        MapClusteredMarkerLayer.debugRecomputeCount++;
        MapClusteredMarkerLayer.debugRecomputeByLayer.update(
          widget.layerKey,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
        return true;
      }());
      _clusterZoom = clusterZoom;
      _layer = MarkerLayer(
        key: ValueKey(widget.layerKey),
        markers: [
          for (final group in widget.groups)
            ...clusterMarkerSpecs(
              group.specs,
              camera: camera,
              clusterKind: group.kind,
              label: group.label,
              onClusterTap: widget.onClusterTap,
            ),
        ],
      );
    }
    return _layer!;
  }
}

List<Marker> clusterMarkerSpecs(
  List<MapMarkerSpec> specs, {
  required MapCamera camera,
  required MapMarkerVisualKind clusterKind,
  required String label,
  required void Function(LatLng point) onClusterTap,
}) {
  if (specs.isEmpty) return const <Marker>[];
  // Group on a whole zoom level: the pixel grid is then fixed for the whole
  // level instead of sliding under the pins on every frame of a pinch.
  final clusterZoom = mapClusterZoomLevel(camera.zoom);
  final cellSize = mapClusterCellSizeForZoom(clusterZoom);
  if (cellSize == null) {
    return [
      for (final spec in specs)
        Marker(
          key: ValueKey<String>('marker:${clusterKind.name}:${spec.id}'),
          point: spec.point,
          width: spec.width,
          height: spec.height,
          child: spec.child,
        ),
    ];
  }

  final groups = <String, List<MapMarkerSpec>>{};
  for (final spec in specs) {
    final projected = camera.projectAtZoom(spec.point, clusterZoom);
    final cellX = (projected.dx / cellSize).floor();
    final cellY = (projected.dy / cellSize).floor();
    groups.putIfAbsent('$cellX:$cellY', () => []).add(spec);
  }

  return [
    for (final entry in groups.entries)
      if (entry.value.length == 1)
        Marker(
          key: ValueKey<String>(
              'marker:${clusterKind.name}:${entry.value.single.id}'),
          point: entry.value.single.point,
          width: entry.value.single.width,
          height: entry.value.single.height,
          child: entry.value.single.child,
        )
      else
        _clusterMarker(entry, clusterKind, label, onClusterTap),
  ];
}

Marker _clusterMarker(
  MapEntry<String, List<MapMarkerSpec>> entry,
  MapMarkerVisualKind kind,
  String label,
  void Function(LatLng point) onTap,
) {
  final center = _clusterCenter(entry.value);
  return Marker(
    key: ValueKey<String>('cluster:${kind.name}:${entry.key}'),
    point: center,
    width: 64,
    height: 52,
    child: MapClusterVisual(
      count: entry.value.length,
      kind: kind,
      label: label,
      onTap: () => onTap(center),
    ),
  );
}

LatLng _clusterCenter(List<MapMarkerSpec> specs) {
  var latitude = 0.0;
  var longitude = 0.0;
  for (final spec in specs) {
    latitude += spec.point.latitude;
    longitude += spec.point.longitude;
  }
  return LatLng(latitude / specs.length, longitude / specs.length);
}
