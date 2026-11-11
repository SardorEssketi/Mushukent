// My lost-pet reports and My adoption posts show their empty message centred,
// like the other "My ..." activity lists, and keep pull-to-refresh.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';
import 'package:mushukistan_frontend/features/adoption_posts/presentation/screens/my_adoption_posts_screen.dart';
import 'package:mushukistan_frontend/features/lost_pets/presentation/screens/my_lost_pets_screen.dart';

import '../../support/fakes.dart';

const _emptyPage = {'items': <Object?>[], 'next_cursor': null, 'limit': 50};

Future<FakeApiClient> _pump(
    WidgetTester tester, String path, Widget screen) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final client = FakeApiClient()..setHandler('GET', path, (_) => _emptyPage);
  final container = ProviderContainer(overrides: [
    mushukistanApiProvider.overrideWithValue(MushukistanApi(client: client)),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(home: screen),
  ));
  await tester.pumpAndSettle();
  return client;
}

void main() {
  for (final (name, path, screen, message) in [
    (
      'My lost-pet reports',
      'lost-pets/mine',
      const MyLostPetsScreen(),
      'No lost pets yet.',
    ),
    (
      'My adoption posts',
      'adoption-posts/mine',
      const MyAdoptionPostsScreen(),
      'No rehoming posts yet.',
    ),
  ]) {
    testWidgets('$name: empty message is centred and refreshable',
        (tester) async {
      final client = await _pump(tester, path, screen);
      final empty = find.byKey(const ValueKey('my-activity-empty'));
      expect(empty, findsOneWidget);
      expect(find.text(message), findsOneWidget);
      final body = tester.getRect(find.byType(RefreshIndicator));
      final center = tester.getCenter(empty);
      expect((center.dx - body.center.dx).abs(), lessThan(1));
      expect((center.dy - body.center.dy).abs(), lessThan(1));

      final before = client.calls.length;
      await tester.fling(empty, const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      expect(client.calls.length, before + 1);
    });
  }
}
