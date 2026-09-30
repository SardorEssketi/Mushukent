import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/features/map/presentation/widgets/map_floating_controls.dart';
import 'package:mushukistan_frontend/features/map/presentation/widgets/map_marker_visual.dart';

void main() {
  test('each Map category uses a distinct symbol', () {
    final icons = MapMarkerVisualKind.values.map(mapVisualIcon).toSet();
    expect(icons, hasLength(MapMarkerVisualKind.values.length));
  });

  testWidgets('individual marker is compact inside a 52 pixel target',
      (tester) async {
    for (final kind in MapMarkerVisualKind.values) {
      await tester.pumpWidget(MaterialApp(
        home: Center(
          child: SizedBox.square(
            dimension: 52,
            child: MapMarkerVisual(
              kind: kind,
              label: kind.name,
              onTap: () {},
            ),
          ),
        ),
      ));
      final graphic = find.byKey(const ValueKey('map-marker-graphic'));
      expect(tester.getSize(graphic).width, lessThanOrEqualTo(36));
      expect(find.byIcon(mapVisualIcon(kind)), findsOneWidget);
    }
  });

  testWidgets('cluster integrates category and count in one graphic',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: SizedBox(
          width: 64,
          height: 52,
          child: MapClusterVisual(
            kind: MapMarkerVisualKind.veterinary,
            label: 'Vets',
            count: 12,
            onTap: () {},
          ),
        ),
      ),
    ));
    final graphic = find.byKey(const ValueKey('map-cluster-graphic'));
    expect(graphic, findsOneWidget);
    expect(find.descendant(of: graphic, matching: find.text('12')),
        findsOneWidget);
    expect(
        find.descendant(
            of: graphic,
            matching:
                find.byIcon(mapVisualIcon(MapMarkerVisualKind.veterinary))),
        findsOneWidget);
    expect(find.byTooltip('Vets: 12'), findsOneWidget);
  });

  testWidgets('filtered layers are visible without a wide toolbar',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: MapLayersControl(
          label: 'Filters',
          selectedCount: 4,
          totalCount: 6,
          loading: false,
          onPressed: () {},
        ),
      ),
    ));
    expect(find.text('4'), findsOneWidget);
    expect(find.byTooltip('Filters · 4/6'), findsOneWidget);
    expect(tester.getSize(find.byType(MapLayersControl)).width, 64);
  });

  testWidgets('location glyph remains present in light and dark themes',
      (tester) async {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.brown, brightness: brightness)),
        home: Center(
          child: MapLocationControl(
            label: 'Center on user',
            active: brightness == Brightness.dark,
            busy: false,
            onPressed: () {},
          ),
        ),
      ));
      expect(find.byTooltip('Center on user'), findsOneWidget);
      expect(
          find.descendant(
              of: find.byType(MapLocationControl),
              matching: find.byType(CustomPaint)),
          findsWidgets);
      expect(tester.getSize(find.byType(MapLocationControl)).width, 52);
    }
  });
}
