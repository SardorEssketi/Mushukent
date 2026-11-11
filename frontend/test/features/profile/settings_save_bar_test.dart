// Settings: the Save button is pinned to the bottom of the screen and only
// shows while there is something to save, so it is never hidden below the list.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';
import 'package:mushukistan_frontend/features/profile/presentation/screens/profile_screen.dart';
import 'package:mushukistan_frontend/features/profile/presentation/screens/settings_screen.dart';

import '../../support/fakes.dart';

const _saveBar = ValueKey('settings-save-bar');
const _saveButton = ValueKey('settings-save-button');

Map<String, Object?> _profileJson({bool allowPublicActivityView = true}) => {
      'id': '11111111-1111-4111-8111-111111111111',
      'email': 'test@example.com',
      'registered_at': '2026-01-01T00:00:00Z',
      'observation_count': 0,
      'total_likes_received': 0,
      'comment_count': 0,
      'allow_public_activity_view': allowPublicActivityView,
    };

Future<(FakeApiClient, GoRouter)> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final client = FakeApiClient()
    ..setHandler('GET', 'users/me', (_) => _profileJson())
    ..setHandler('PATCH', 'users/me', (_) => _profileJson());
  final container = ProviderContainer(overrides: [
    mushukistanApiProvider.overrideWithValue(MushukistanApi(client: client)),
    profileMeProvider.overrideWith((ref) async => UserProfileData(
          id: '11111111-1111-4111-8111-111111111111',
          email: 'test@example.com',
          registeredAt: DateTime.utc(2026, 1, 1),
          observationCount: 0,
          totalLikesReceived: 0,
          commentCount: 0,
        )),
  ]);
  final router = GoRouter(
    initialLocation: '/profile/settings',
    routes: [
      GoRoute(
        path: '/profile',
        builder: (_, __) => const Scaffold(body: Text('Profile')),
        routes: [
          GoRoute(
            path: 'settings',
            builder: (_, __) => const SettingsScreen(),
          ),
        ],
      ),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(router.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return (client, router);
}

void main() {
  testWidgets('Save appears pinned on screen after any change', (tester) async {
    await _pump(tester);
    expect(find.byKey(_saveBar), findsNothing);
    expect(find.text('Save changes'), findsNothing);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(find.byKey(_saveBar), findsOneWidget);
    // Visible without scrolling: the button sits inside the screen.
    final rect = tester.getRect(find.byKey(_saveButton));
    final barHeight = tester.getSize(find.byKey(_saveBar)).height;
    expect(rect.bottom, lessThanOrEqualTo(700));
    expect(rect.top, greaterThan(0));

    // The bar stays in place while the list scrolls.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(_saveButton)), rect);

    // Undoing the change hides it again.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Auto'));
    // It collapses smoothly instead of vanishing at once.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(_saveBar), findsOneWidget);
    final collapsing = tester
        .getSize(find.ancestor(
            of: find.byKey(_saveBar), matching: find.byType(SizeTransition)))
        .height;
    expect(collapsing, greaterThan(0));
    expect(collapsing, lessThan(barHeight));
    await tester.pumpAndSettle();
    expect(find.byKey(_saveBar), findsNothing);
  });

  testWidgets('language and privacy changes also show Save', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Russian'));
    await tester.pumpAndSettle();
    expect(find.byKey(_saveBar), findsOneWidget);
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(find.byKey(_saveBar), findsNothing);

    await tester.scrollUntilVisible(find.byType(SwitchListTile), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(find.byKey(_saveBar), findsOneWidget);
  });

  testWidgets('tapping the pinned Save saves and returns to Profile',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    final (client, router) = await _pump(tester);
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_saveButton));
    await tester.pumpAndSettle();
    expect(client.calls.where((c) => c.method == 'PATCH'), hasLength(1));
    expect(router.routeInformationProvider.value.uri.path, '/profile');
  });
}
