import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mushukistan_frontend/core/localization/language_controller.dart';
import 'package:mushukistan_frontend/features/auth/application/auth_controller.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_models.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_repository.dart';
import 'package:mushukistan_frontend/features/notifications/application/nearby_alerts.dart';
import 'package:mushukistan_frontend/features/notifications/application/notification_push.dart';
import 'package:mushukistan_frontend/features/notifications/data/notification_api.dart';

import 'nearby_alerts_test.dart'
    show AuthorizedLocationFake, MemoryConsent, NearbyApiFake;
import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('mushukistan/notification_settings');

  test('Android OS permission is readable without configured Firebase',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    String status = 'allowed';
    int opened = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'notificationPermissionStatus') return status;
      if (call.method == 'openNotificationSettings') opened++;
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    final access = DevicePushAccess();
    expect(access.available, false);
    expect(await access.status(), DevicePushPermission.allowed);
    status = 'denied';
    expect(await access.status(), DevicePushPermission.denied);
    await access.openSettings();
    expect(opened, 1);
  });

  testWidgets(
      'automatic location refresh runs on launch/resume, not rebuild or pause',
      (tester) async {
    final location = AuthorizedLocationFake();
    final api = NearbyApiFake();
    final consent = MemoryConsent()..choices['owner'] = true;
    final nearby = NearbyAlerts(
        api: api,
        location: location,
        consent: consent,
        android: true,
        currentUser: () => 'owner');
    final client = FakeApiClient();
    client.setHandler('POST', 'notifications/activity', (_) => null);
    final router = GoRouter(routes: [
      GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: Text('Application')))
    ]);
    addTearDown(router.dispose);
    final container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(
        restoreResult: SessionRestoreSuccess(AuthSession.restored(
          accessToken: 'test-token',
          user: MushukistanUser(id: 'owner', registeredAt: DateTime(2026)),
        )),
      )),
      googleIdentityTokenProvider
          .overrideWithValue(FakeGoogleIdentityTokenProvider()),
      notificationApiProvider.overrideWithValue(NotificationApi(client)),
      nearbyAlertsProvider.overrideWith((ref) => nearby),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: Consumer(builder: (context, ref, _) {
          ref.watch(appLanguageProvider);
          return NotificationLifecycle(
              router: router, child: MaterialApp.router(routerConfig: router));
        })));
    await tester.pumpAndSettle();
    expect(location.fixes, 1);
    container.read(appLanguageProvider.notifier).state = AppLanguage.russian;
    await tester.pumpAndSettle();
    expect(location.fixes, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(location.fixes, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(location.fixes, 2);
    expect(location.permissionRequests, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'first launch shows localized consent before uploading a location',
      (tester) async {
    final location = AuthorizedLocationFake();
    final api = NearbyApiFake();
    final consent = MemoryConsent();
    final nearby = NearbyAlerts(
        api: api,
        location: location,
        consent: consent,
        android: true,
        currentUser: () => 'owner');
    final client = FakeApiClient();
    client.setHandler('POST', 'notifications/activity', (_) => null);
    final router = GoRouter(routes: [
      GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: Text('Application')))
    ]);
    addTearDown(router.dispose);
    final container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(
        restoreResult: SessionRestoreSuccess(AuthSession.restored(
          accessToken: 'test-token',
          user: MushukistanUser(id: 'owner', registeredAt: DateTime(2026)),
        )),
      )),
      googleIdentityTokenProvider
          .overrideWithValue(FakeGoogleIdentityTokenProvider()),
      appLanguageProvider.overrideWith((ref) => AppLanguage.russian),
      notificationApiProvider.overrideWithValue(NotificationApi(client)),
      nearbyAlertsProvider.overrideWith((ref) => nearby),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: NotificationLifecycle(
            router: router, child: MaterialApp.router(routerConfig: router))));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('500 м'), findsOneWidget);
    expect(location.fixes, 0);
    expect(api.patches.single,
        {'nearby_enabled': false, 'expected_user_id': 'owner'});
    await tester.tap(find.text('Разрешить приватные оповещения рядом'));
    await tester.pumpAndSettle();
    expect(consent.choices['owner'], true);
    expect(location.fixes, 1);
    expect(api.patches.last['nearby_consent'], true);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
