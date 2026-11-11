import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mushukistan_frontend/features/map/presentation/widgets/map_clustered_marker_layer.dart';
import 'package:mushukistan_frontend/features/map/presentation/widgets/map_marker_visual.dart';

void main() {
  testWidgets('pan retains clusters while zoom recomputes them',
      (tester) async {
    final controller = MapController();
    addTearDown(controller.dispose);
    const point = LatLng(41.2995, 69.2401);
    final groups = [
      const MapMarkerGroup(
        kind: MapMarkerVisualKind.petShop,
        label: 'Shops',
        specs: [
          MapMarkerSpec(id: 'one', point: point, child: SizedBox()),
          MapMarkerSpec(
              id: 'two', point: LatLng(41.2997, 69.2403), child: SizedBox()),
        ],
      ),
    ];
    MapClusteredMarkerLayer.debugRecomputeByLayer.clear();
    await tester.pumpWidget(MaterialApp(
      home: FlutterMap(
        mapController: controller,
        options: const MapOptions(initialCenter: point, initialZoom: 13.6),
        children: [
          MapClusteredMarkerLayer(
            groups: groups,
            layerKey: 'probe-layer',
            onClusterTap: (_) {},
          ),
        ],
      ),
    ));
    final initial =
        MapClusteredMarkerLayer.debugRecomputeByLayer['probe-layer'];
    expect(initial, 1);
    controller.move(const LatLng(41.3000, 69.2500), 13.6);
    await tester.pump();
    expect(
        MapClusteredMarkerLayer.debugRecomputeByLayer['probe-layer'], initial);
    controller.move(const LatLng(41.3000, 69.2500), 15);
    await tester.pump();
    expect(MapClusteredMarkerLayer.debugRecomputeByLayer['probe-layer'],
        initial! + 1);
  });

  testWidgets('fractional pinch zoom keeps clusters stable within a level',
      (tester) async {
    final controller = MapController();
    addTearDown(controller.dispose);
    const center = LatLng(41.2995, 69.2401);
    final specs = [
      for (var i = 0; i < 40; i++)
        MapMarkerSpec(
          id: 'p$i',
          point: LatLng(41.29 + (i % 8) * 0.0021, 69.23 + (i ~/ 8) * 0.0027),
          child: const SizedBox(),
        ),
    ];
    final groups = [
      MapMarkerGroup(
          kind: MapMarkerVisualKind.petShop, label: 'Shops', specs: specs),
    ];
    MapClusteredMarkerLayer.debugRecomputeByLayer.clear();
    await tester.pumpWidget(MaterialApp(
      home: FlutterMap(
        mapController: controller,
        options: const MapOptions(initialCenter: center, initialZoom: 13.1),
        children: [
          MapClusteredMarkerLayer(
            groups: groups,
            layerKey: 'pinch-layer',
            onClusterTap: (_) {},
          ),
        ],
      ),
    ));
    List<(Key?, LatLng)> snapshot() => [
          for (final marker in tester
              .widget<MarkerLayer>(find.byKey(const ValueKey('pinch-layer')))
              .markers)
            (marker.key, marker.point),
        ];
    final initial = snapshot();
    expect(initial.length, lessThan(specs.length));
    for (var zoom = 13.15; zoom < 14; zoom += 0.05) {
      controller.move(center, zoom);
      await tester.pump();
      expect(snapshot(), initial, reason: 'zoom $zoom');
    }
    expect(MapClusteredMarkerLayer.debugRecomputeByLayer['pinch-layer'], 1);
    controller.move(center, 14.2);
    await tester.pump();
    expect(MapClusteredMarkerLayer.debugRecomputeByLayer['pinch-layer'], 2);
  });
}
