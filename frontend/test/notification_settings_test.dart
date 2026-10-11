import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mushukistan_frontend/core/location/location_service.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';
import 'package:mushukistan_frontend/features/notifications/application/notification_push.dart';
import 'package:mushukistan_frontend/features/notifications/data/notification_api.dart';
import 'package:mushukistan_frontend/features/notifications/presentation/notification_settings_screen.dart';

import 'support/fakes.dart';

class _PushAccess extends DevicePushAccess {
  _PushAccess(this.current);
  DevicePushPermission current;
  int openedSettings = 0;
  int requested = 0;

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

class _Location extends LocationService {
  int requests = 0;

  @override
  Future<GeoPoint?> resolveCurrentLocation() async {
    requests++;
    return const GeoPoint(latitude: 41.3, longitude: 69.2);
  }
}

Map<String, Object?> _preferences({
  bool nearby = false,
  Map<String, Object?>? point,
}) =>
    {
      'push_comments': true,
      'push_replies': false,
      'push_followups': true,
      'nearby_enabled': nearby,
      'inactivity_enabled': false,
      'push_available': true,
      'alert_location': point,
    };

Future<(FakeApiClient, _PushAccess, _Location)> _mount(
  WidgetTester tester, {
  DevicePushPermission status = DevicePushPermission.denied,
  Map<String, Object?>? initialPreferences,
  bool failLoad = false,
}) async {
  final client = FakeApiClient();
  final preferences = initialPreferences ?? _preferences();
  final push = _PushAccess(status);
  final location = _Location();
  client.setHandler('GET', 'notifications/preferences', (_) {
    if (failLoad) throw StateError('offline');
    return {...preferences};
  });
  client.setHandler('PATCH', 'notifications/preferences', (call) {
    final patch = call.body! as Map<String, Object?>;
    preferences.addAll(patch);
    if (patch['nearby_enabled'] == false) preferences['alert_location'] = null;
    return {...preferences};
  });
  await tester.pumpWidget(ProviderScope(
    overrides: [
      notificationApiProvider.overrideWithValue(NotificationApi(client)),
      devicePushAccessProvider.overrideWithValue(push),
      locationServiceProvider.overrideWithValue(location),
    ],
    child: const MaterialApp(home: NotificationSettingsScreen()),
  ));
  await tester.pumpAndSettle();
  return (client, push, location);
}

Future<void> _showNearby(WidgetTester tester) async {
  await tester.scrollUntilVisible(find.text('Nearby Lost Pets'), 180,
      scrollable: find.byType(Scrollable).first);
  await tester.pump();
}

void main() {
  testWidgets('permission denial does not disable server preferences',
      (tester) async {
    final (client, _, _) = await _mount(tester);
    expect(find.text('Notifications are off on this device'), findsOneWidget);
    final comments = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'Comments on my posts'),
    );
    expect(comments.value, isTrue);
    expect(comments.onChanged, isNotNull);
    expect(
        tester
            .widget<SwitchListTile>(
              find.widgetWithText(SwitchListTile, 'Replies to my comments'),
            )
            .value,
        isFalse);
    await tester.tap(find.text('Comments on my posts'));
    await tester.pumpAndSettle();
    expect((client.calls.last.body as Map)['push_comments'], false);
    expect(
        tester
            .widget<SwitchListTile>(
              find.widgetWithText(SwitchListTile, 'Comments on my posts'),
            )
            .value,
        isFalse);
  });

  testWidgets('permanent denial points to Android settings', (tester) async {
    final (_, access, _) =
        await _mount(tester, status: DevicePushPermission.deniedPermanently);
    await tester.tap(find.text('Open Android settings'));
    await tester.pump();
    expect(access.openedSettings, 1);
    expect(access.requested, 0);
  });

  testWidgets('unconfigured push has no misleading permission action',
      (tester) async {
    await _mount(tester, status: DevicePushPermission.unavailable);
    expect(find.text('Device push is unavailable'), findsOneWidget);
    expect(find.text('Enable notifications'), findsNothing);
    expect(find.text('Open Android settings'), findsNothing);
    expect(
      tester
          .widget<SwitchListTile>(
            find.widgetWithText(SwitchListTile, 'Comments on my posts'),
          )
          .onChanged,
      isNotNull,
    );
  });

  testWidgets('enabling a push category asks permission only after context',
      (tester) async {
    final (client, access, _) = await _mount(
      tester,
      status: DevicePushPermission.notDetermined,
    );
    expect(access.requested, 0);
    await tester.tap(find.text('Replies to my comments'));
    await tester.pumpAndSettle();
    expect((client.calls.last.body as Map)['push_replies'], true);
    expect(find.textContaining('Allow Android notifications'), findsOneWidget);
    expect(access.requested, 0);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(access.requested, 1);
    expect(
      tester
          .widget<SwitchListTile>(
            find.widgetWithText(SwitchListTile, 'Replies to my comments'),
          )
          .value,
      isTrue,
    );
  });

  testWidgets(
      'nearby needs a point; map selection saves and disabling clears it',
      (tester) async {
    final (client, _, _) = await _mount(tester);
    await _showNearby(tester);
    expect(find.byType(FlutterMap), findsNothing);
    await tester.tap(find.text('Nearby Lost Pets'));
    await tester.pump();
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(client.calls.where((call) => call.method == 'PATCH'), isEmpty);
    final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
    map.options.onTap!(
      const TapPosition(Offset.zero, Offset.zero),
      const LatLng(41.3, 69.2),
    );
    await tester.pump();
    await tester.ensureVisible(find.text('Save point and turn on alerts'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save point and turn on alerts'));
    await tester.pumpAndSettle();
    final patch = client.calls.last.body as Map;
    expect(patch['nearby_enabled'], true);
    expect((patch['alert_location'] as Map)['latitude'], 41.3);
    await tester.ensureVisible(find.text('Nearby Lost Pets'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nearby Lost Pets'));
    await tester.pumpAndSettle();
    expect((client.calls.last.body as Map)['nearby_enabled'], false);
    expect(find.byType(FlutterMap), findsNothing);
  });

  testWidgets(
      'one-time current location selects a point but does not upload it',
      (tester) async {
    final (client, _, location) = await _mount(tester);
    await _showNearby(tester);
    await tester.ensureVisible(find.text('Use my current location once'));
    await tester.tap(find.text('Use my current location once'));
    await tester.pumpAndSettle();
    expect(location.requests, 1);
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(client.calls.where((call) => call.method == 'PATCH'), isEmpty);
  });

  testWidgets('saved point has compact preview and change action',
      (tester) async {
    await _mount(tester,
        initialPreferences: _preferences(
          nearby: true,
          point: {'latitude': 41.3, 'longitude': 69.2},
        ));
    await _showNearby(tester);
    expect(tester.getSize(find.byType(FlutterMap)).height, 140);
    await tester.ensureVisible(find.text('Change alert point'));
    await tester.tap(find.text('Change alert point'));
    await tester.pump();
    expect(tester.getSize(find.byType(FlutterMap)).height, 210);
  });

  testWidgets('load failure has a retry action and compact layout is bounded',
      (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _mount(tester, failLoad: true);
    expect(find.text('Try again'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('loaded settings fit a compact screen without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _mount(tester);
    await _showNearby(tester);
    expect(tester.takeException(), isNull);
  });
}
