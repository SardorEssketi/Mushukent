import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';
import 'package:mushukistan_frontend/core/navigation/settings_changes_guard.dart';
import 'package:mushukistan_frontend/features/profile/presentation/screens/profile_screen.dart';
import 'package:mushukistan_frontend/features/profile/presentation/screens/settings_screen.dart';

void main() {
  testWidgets('Settings links to Notifications and guards pending edits',
      (tester) async {
    final container = ProviderContainer(overrides: [
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
              routes: [
                GoRoute(
                  path: 'notifications',
                  builder: (_, __) =>
                      const Scaffold(body: Text('Notification preferences')),
                ),
              ],
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
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Notifications'), 180,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Notifications'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'About account'), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, 'Notifications'));
    await tester.pumpAndSettle();
    expect(find.text('Unsaved changes'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/profile/settings');
    expect(find.text('Unsaved changes'), findsNothing);
    await tester.tap(find.widgetWithText(ListTile, 'Notifications'));
    await tester.pumpAndSettle();
    expect(find.text('Unsaved changes'), findsOneWidget);
    await tester.tap(find.text('Discard changes'));
    await tester.pumpAndSettle();
    expect(container.read(settingsHasUnsavedChangesProvider), isFalse);
    expect(find.text('Notification preferences'), findsOneWidget);
  });
}
