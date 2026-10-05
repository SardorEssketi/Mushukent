import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';
import 'package:mushukistan_frontend/features/add_observation/application/add_observation_controller.dart';
import 'package:mushukistan_frontend/features/add_observation/presentation/screens/add_observation_location_screen.dart';

void main() {
  testWidgets('map picker returns a point without losing the draft',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller =
        container.read(addObservationControllerProvider.notifier);
    controller.setKind('needs_help');
    controller.setCatName('Mimi');
    controller.setDescription('Injured paw');
    controller.setLocation(const GeoPoint(latitude: 41.30, longitude: 69.25));
    final router = GoRouter(initialLocation: '/add/location', routes: [
      GoRoute(
        path: '/add/location',
        builder: (_, __) => const AddObservationLocationScreen(),
      ),
      GoRoute(
        path: '/add/details',
        builder: (_, __) => const Scaffold(body: Text('Form destination')),
      ),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(FlutterMap), findsOneWidget);
    tester.widget<FlutterMap>(find.byType(FlutterMap)).options.onTap!(
      const TapPosition(Offset.zero, Offset.zero),
      const LatLng(41.31, 69.28),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Use this location'))
          .onPressed,
      isNotNull,
    );
    await tester.ensureVisible(find.text('Use this location'));
    await tester.tap(find.text('Use this location'));
    await tester.pumpAndSettle();
    expect(find.text('Form destination'), findsOneWidget);
    final draft = container.read(addObservationControllerProvider);
    expect(draft.kind, 'needs_help');
    expect(draft.catName, 'Mimi');
    expect(draft.description, 'Injured paw');
    expect(draft.location, isNotNull);
    expect(draft.location!.latitude, 41.31);
    expect(draft.location!.longitude, 69.28);
  });
}
