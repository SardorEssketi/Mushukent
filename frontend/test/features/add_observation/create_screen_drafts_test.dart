import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mushukistan_frontend/core/localization/language_controller.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';
import 'package:mushukistan_frontend/features/add_observation/application/add_observation_controller.dart';
import 'package:mushukistan_frontend/features/add_observation/presentation/screens/add_observation_screen.dart';
import 'package:mushukistan_frontend/features/adoption_posts/presentation/screens/adoption_post_create_screen.dart';
import 'package:mushukistan_frontend/features/lost_pets/presentation/screens/lost_pet_create_screen.dart';

import '../../support/fakes.dart';

/// Lost Pet and Rehoming keep no draft: their form lives in the screen and is
/// discarded on leave. Opening one must never surface "Continue draft".
Future<(ProviderContainer, GoRouter)> _mount(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(overrides: [
    mushukistanApiProvider
        .overrideWithValue(MushukistanApi(client: FakeApiClient())),
    appLanguageProvider.overrideWith((ref) => AppLanguage.english),
  ]);
  addTearDown(container.dispose);
  final router = GoRouter(initialLocation: '/add', routes: [
    GoRoute(
      path: '/add',
      builder: (_, __) => const AddObservationScreen(),
      routes: [
        GoRoute(
            path: 'lost-pet', builder: (_, __) => const LostPetCreateScreen()),
        GoRoute(
            path: 'adoption',
            builder: (_, __) => const AdoptionPostCreateScreen()),
      ],
    ),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return (container, router);
}

void main() {
  for (final path in ['/add/lost-pet', '/add/adoption']) {
    testWidgets('$path: opening and leaving without input leaves no draft',
        (tester) async {
      final (container, router) = await _mount(tester);
      router.go(path);
      await tester.pumpAndSettle();
      router.go('/add');
      await tester.pumpAndSettle();
      expect(find.text('Continue draft'), findsNothing);
      expect(
          container.read(addObservationControllerProvider).hasDraft, isFalse);
    });

    testWidgets('$path: a description is discarded on leave, not kept as draft',
        (tester) async {
      final (container, router) = await _mount(tester);
      router.go(path);
      await tester.pumpAndSettle();
      final info = find.widgetWithText(TextFormField, 'Additional information');
      expect(info, findsOneWidget);
      await tester.enterText(info, 'Grey tabby, blue collar');
      router.go('/add');
      await tester.pumpAndSettle();
      expect(find.text('Continue draft'), findsNothing);
      expect(
          container.read(addObservationControllerProvider).hasDraft, isFalse);
      router.go(path);
      await tester.pumpAndSettle();
      expect(find.text('Grey tabby, blue collar'), findsNothing);
    });
  }
}
