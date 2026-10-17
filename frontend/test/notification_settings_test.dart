import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/core/location/location_service.dart';
import 'package:mushukistan_frontend/features/notifications/application/nearby_alerts.dart';
import 'package:mushukistan_frontend/features/notifications/application/notification_push.dart';
import 'package:mushukistan_frontend/features/notifications/data/notification_api.dart';
import 'package:mushukistan_frontend/features/notifications/presentation/notification_settings_screen.dart';

import 'nearby_alerts_test.dart' show AuthorizedLocationFake, MemoryConsent;
import 'support/fakes.dart';

class _PushAccess extends DevicePushAccess {
  _PushAccess(this.current, this.configured);
  DevicePushPermission current;
  final bool configured;
  int openedSettings = 0;
  int requested = 0;
  @override
  bool get available => configured;
  @override
  Future<DevicePushPermission> status() async => current;
  @override
  Future<bool> requestPermission() async {
    requested++;
    return false;
  }

  @override
  Future<void> openSettings() async {
    openedSettings++;
  }
}

Future<(FakeApiClient, _PushAccess, AuthorizedLocationFake)> mountSettings(
  WidgetTester tester, {
  DevicePushPermission permission = DevicePushPermission.denied,
  AuthorizedLocationStatus locationPermission = AuthorizedLocationStatus.denied,
  bool configured = true,
  bool android = true,
  bool failLoad = false,
}) async {
  final client = FakeApiClient();
  client.setHandler('GET', 'notifications/preferences', (_) {
    if (failLoad) throw StateError('offline');
    return {
      'push_comments': true,
      'push_replies': true,
      'push_followups': true,
      'nearby_enabled': false,
      'inactivity_enabled': true,
      'push_available': configured,
      'alert_location': null
    };
  });
  final push = _PushAccess(permission, configured);
  final location = AuthorizedLocationFake()..permission = locationPermission;
  final api = NotificationApi(client);
  final nearby = NearbyAlerts(
      api: api,
      location: location,
      consent: MemoryConsent(),
      android: android,
      currentUser: () => 'owner');
  await tester.pumpWidget(ProviderScope(overrides: [
    notificationApiProvider.overrideWithValue(api),
    devicePushAccessProvider.overrideWithValue(push),
    locationServiceProvider.overrideWithValue(location),
    nearbyAlertsAndroidProvider.overrideWithValue(android),
    nearbyAlertsProvider.overrideWith((ref) => nearby),
  ], child: const MaterialApp(home: NotificationSettingsScreen())));
  await tester.pumpAndSettle();
  return (client, push, location);
}

void main() {
  testWidgets(
      'status screen is read-only, with no category switches, map or save action',
      (tester) async {
    final (client, push, location) = await mountSettings(tester);
    expect(find.byType(SwitchListTile), findsNothing);
    expect(find.byType(FlutterMap), findsNothing);
    expect(find.textContaining('Save'), findsNothing);
    expect(find.text('Not allowed'), findsOneWidget);
    expect(find.textContaining('500 m'), findsOneWidget);
    expect(client.calls.where((call) => call.method == 'PATCH'), isEmpty);
    expect(location.fixes, 0);
    expect(push.requested, 0);
  });

  testWidgets(
      'denied notification permission opens Android notification settings',
      (tester) async {
    final (_, push, _) = await mountSettings(tester,
        permission: DevicePushPermission.deniedPermanently);
    await tester.tap(find.text('Open Android settings'));
    await tester.pump();
    expect(push.openedSettings, 1);
    expect(push.requested, 0);
  });

  testWidgets(
      'location denial opens Android location settings, without a map action',
      (tester) async {
    final (_, _, location) = await mountSettings(tester);
    await tester.ensureVisible(find.text('Open Android location permissions'));
    await tester.tap(find.text('Open Android location permissions'));
    await tester.pump();
    expect(location.settings, 1);
    expect(location.permissionRequests, 0);
  });

  testWidgets('permission and configured push delivery are separate statuses',
      (tester) async {
    await mountSettings(tester,
        permission: DevicePushPermission.allowed, configured: false);
    expect(find.text('Allowed'), findsOneWidget);
    expect(
        find.textContaining('Unavailable: Android permission'), findsOneWidget);
    expect(find.text('Open Android settings'), findsNothing);
  });

  testWidgets('configured allowed push is available', (tester) async {
    await mountSettings(tester, permission: DevicePushPermission.allowed);
    expect(find.text('Available on this device'), findsOneWidget);
  });

  testWidgets('web has no Android permission or location controls',
      (tester) async {
    await mountSettings(tester,
        permission: DevicePushPermission.web, android: false);
    expect(find.text('Open Android settings'), findsNothing);
    expect(find.text('Open Android location permissions'), findsNothing);
    expect(find.textContaining('Notification Center works'), findsOneWidget);
  });

  testWidgets('offline screen offers retry; compact screen has no overflow',
      (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mountSettings(tester, failLoad: true);
    expect(find.text('Try again'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
