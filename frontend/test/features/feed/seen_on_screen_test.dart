import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/features/feed/presentation/widgets/seen_on_screen.dart';

void main() {
  late List<int> seen;
  late ScrollController controller;

  setUp(() {
    seen = <int>[];
    controller = ScrollController();
  });

  Future<void> pumpList(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView.builder(
            controller: controller,
            itemCount: 20,
            itemBuilder: (context, index) => SeenOnScreen(
              key: ValueKey(index),
              onSeen: () => seen.add(index),
              child: SizedBox(height: 250, child: Text('card $index')),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('counts cards that stay half visible for a second',
      (tester) async {
    await pumpList(tester);
    await tester.pump(const Duration(milliseconds: 900));
    expect(seen, isEmpty);

    await tester.pump(const Duration(milliseconds: 200));
    // 600px viewport: card 0 and 1 fully, card 2 shows 100 of 250px.
    expect(seen, [0, 1]);
  });

  testWidgets('cards scrolled past quickly are not counted', (tester) async {
    await pumpList(tester);
    await tester.pump(const Duration(milliseconds: 300));
    controller.jumpTo(250.0 * 10);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1100));

    expect(seen, containsAll([10, 11]));
    expect(seen, isNot(contains(0)));
    expect(seen, isNot(contains(1)));
  });

  testWidgets('each card is counted once', (tester) async {
    await pumpList(tester);
    await tester.pump(const Duration(seconds: 2));
    controller.jumpTo(10);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(seen.where((index) => index == 0), hasLength(1));
  });

  testWidgets('nothing is counted without a scrollable', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SeenOnScreen(
          onSeen: () => seen.add(0),
          child: const SizedBox(height: 100),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(seen, isEmpty);
  });
}
