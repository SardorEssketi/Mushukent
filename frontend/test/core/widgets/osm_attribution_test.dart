import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/core/widgets/osm_attribution.dart';

Widget _map(Widget attribution) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 400,
        height: 400,
        child: FlutterMap(
          options: const MapOptions(),
          children: [attribution],
        ),
      ),
    ),
  );
}

void main() {
  // flutter_test_config.dart collapses the credit for screen tests; test the
  // real five-second display here.
  setUp(() => debugOsmAttributionInitialDisplay = null);
  tearDown(() => debugOsmAttributionInitialDisplay = Duration.zero);

  testWidgets(
      'the credit is visible without interaction, then collapses '
      'to the info button after five seconds', (tester) async {
    await tester.pumpWidget(_map(const OsmAttribution()));
    await tester.pump();

    final credit = find.textContaining('OpenStreetMap contributors');
    expect(credit.hitTestable(), findsOneWidget);
    expect(find.textContaining('©').hitTestable(), findsWidgets);

    await tester.pump(osmAttributionInitialDisplay);
    await tester.pumpAndSettle();
    // Faded out and no longer tappable; the (i) button reopens it.
    expect(credit.hitTestable(), findsNothing);
    await tester.tap(find.byType(IconButton).hitTestable().first);
    await tester.pumpAndSettle();
    expect(credit.hitTestable(), findsOneWidget);
  });

  testWidgets('the credit links to the OpenStreetMap licence page', (
    tester,
  ) async {
    final opened = <Uri>[];
    await tester.pumpWidget(
      _map(OsmAttribution(openUri: (uri) async => opened.add(uri))),
    );
    await tester.pump();

    await tester.tap(find.textContaining('OpenStreetMap contributors'));
    await tester.pump();
    expect(opened, [Uri.parse('https://www.openstreetmap.org/copyright')]);

    await tester.pump(osmAttributionInitialDisplay);
    await tester.pumpAndSettle();
  });

  test('every screen that draws map tiles shows the OpenStreetMap credit', () {
    final withTiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where((file) => file.readAsStringSync().contains('TileLayer('))
        .toList();

    expect(withTiles, isNotEmpty);
    for (final file in withTiles) {
      final source = file.readAsStringSync();
      expect(
        source.contains('OsmAttribution('),
        isTrue,
        reason: '${file.path} draws tiles without OsmAttribution',
      );
    }
  });
}
