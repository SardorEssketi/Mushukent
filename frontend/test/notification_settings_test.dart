import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/core/location/location_service.dart';
import 'package:mushukistan_frontend/features/auth/application/auth_controller.dart';
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

/// Location fake whose permission request returns [afterRequest].
class _Location extends AuthorizedLocationFake {
  AuthorizedLocationStatus afterRequest = AuthorizedLocationStatus.authorized;
  int requests = 0;
  @override
  Future<AuthorizedLocationStatus> requestAuthorization() async {
    requests++;
    permission = afterRequest;
    return afterRequest;
  }
}

class _Harness {
  _Harness(this.client, this.push, this.location, this.consent, this.server,
      this.patchGate);
  final FakeApiClient client;
  final _PushAccess push;
  final _Location location;
  final MemoryConsent consent;

  /// What the fake server currently stores.
  final Map<String, Object?> server;

  /// A failing PATCH waits for this, so the optimistic state can be seen.
  final Completer<void> patchGate;

  List<Map<String, Object?>> get patches => [
        for (final call in client.calls)
          if (call.method == 'PATCH')
            Map<String, Object?>.from(call.body as Map)
      ];
}

const _user = 'owner';

Future<_Harness> _mount(
  WidgetTester tester, {
  DevicePushPermission permission = DevicePushPermission.allowed,
  bool configured = true,
  bool pushAvailable = true,
  AuthorizedLocationStatus locationPermission = AuthorizedLocationStatus.denied,
  bool failPatch = false,
  Map<String, Object?> stored = const {},
}) async {
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final server = <String, Object?>{
    'push_comments': true,
    'push_replies': true,
    'push_followups': true,
    'nearby_enabled': false,
    'inactivity_enabled': true,
    'push_available': pushAvailable,
    'alert_location': null,
    ...stored,
  };
  final patchGate = Completer<void>();
  final client = FakeApiClient()
    ..setHandler('GET', 'notifications/preferences', (_) => {...server})
    ..setHandler('PATCH', 'notifications/preferences', (call) async {
      if (failPatch) {
        await patchGate.future;
        throw StateError('offline');
      }
      final body = Map<String, Object?>.from(call.body as Map);
      for (final field in const [
        'push_comments',
        'push_replies',
        'push_followups',
        'inactivity_enabled',
      ]) {
        if (body.containsKey(field)) server[field] = body[field];
      }
      if (body['nearby_enabled'] == true) {
        server['nearby_enabled'] = true;
        server['alert_location'] = body['alert_location'];
      } else if (body['nearby_enabled'] == false) {
        server['nearby_enabled'] = false;
        server['alert_location'] = null;
      }
      return {...server};
    });
  final push = _PushAccess(permission, configured);
  final location = _Location()..permission = locationPermission;
  final consent = MemoryConsent();
  final api = NotificationApi(client);
  final nearby = NearbyAlerts(
      api: api,
      location: location,
      consent: consent,
      android: true,
      currentUser: () => _user);
  await tester.pumpWidget(ProviderScope(overrides: [
    notificationApiProvider.overrideWithValue(api),
    devicePushAccessProvider.overrideWithValue(push),
    locationServiceProvider.overrideWithValue(location),
    nearbyAlertsAndroidProvider.overrideWithValue(true),
    nearbyAlertsProvider.overrideWith((ref) => nearby),
    nearbyConsentStoreProvider.overrideWithValue(consent),
    currentUserProvider.overrideWithValue(testUser(id: _user)),
  ], child: const MaterialApp(home: NotificationSettingsScreen())));
  await tester.pumpAndSettle();
  return _Harness(client, push, location, consent, server, patchGate);
}

Finder _switch(String field) =>
    find.byKey(ValueKey('notification-switch-$field'));

bool _value(WidgetTester tester, String field) =>
    tester.widget<SwitchListTile>(_switch(field)).value;

const _categories = {
  'push_comments': 'Comments on my posts',
  'push_replies': 'Replies to my comments',
  'push_followups': 'Reminders about my listings',
  'inactivity_enabled': 'Remind me if I haven’t visited for a while',
};

void main() {
  group('notification permission banner', () {
    for (final permission in [
      DevicePushPermission.denied,
      DevicePushPermission.deniedPermanently,
      DevicePushPermission.notDetermined,
    ]) {
      testWidgets('shown when permission is $permission', (tester) async {
        final h = await _mount(tester, permission: permission);
        expect(find.text('Notifications are turned off in your phone settings'),
            findsOneWidget);
        // No account session in this harness: the button opens Android settings.
        await tester.tap(find.text('Turn on'));
        await tester.pumpAndSettle();
        expect(h.push.openedSettings, 1);
      });
    }

    testWidgets('hidden when permission is granted', (tester) async {
      await _mount(tester);
      expect(
          find.byKey(const ValueKey('notifications-off-banner')), findsNothing);
      expect(
          find.byKey(const ValueKey('push-unavailable-warning')), findsNothing);
    });

    testWidgets('granted but push not deliverable: one plain warning line',
        (tester) async {
      await _mount(tester, pushAvailable: false);
      expect(
          find.byKey(const ValueKey('notifications-off-banner')), findsNothing);
      expect(find.byKey(const ValueKey('push-unavailable-warning')),
          findsOneWidget);
    });
  });

  testWidgets('the old technical rows and hints are gone', (tester) async {
    await _mount(tester, permission: DevicePushPermission.denied);
    for (final gone in [
      'Android notification permission',
      'Push delivery',
      'enabled automatically',
      'Notification Center works',
    ]) {
      expect(find.textContaining(gone), findsNothing, reason: gone);
    }
    expect(find.byType(FlutterMap), findsNothing);
    expect(find.textContaining('Save'), findsNothing);
  });

  testWidgets('five switches with the stored values', (tester) async {
    await _mount(tester, stored: {'push_replies': false});
    for (final entry in _categories.entries) {
      expect(find.text(entry.value), findsOneWidget);
    }
    expect(find.text('Lost pets nearby'), findsOneWidget);
    expect(find.text('Lost pets and rehoming'), findsOneWidget);
    expect(_value(tester, 'push_comments'), isTrue);
    expect(_value(tester, 'push_replies'), isFalse);
    expect(_value(tester, 'nearby_enabled'), isFalse);
  });

  for (final entry in _categories.entries) {
    testWidgets('${entry.key}: saves at once with one PATCH', (tester) async {
      final h = await _mount(tester);
      await tester.ensureVisible(_switch(entry.key));
      await tester.tap(_switch(entry.key));
      await tester.pumpAndSettle();
      expect(h.patches, [
        {entry.key: false, 'expected_user_id': _user}
      ]);
      expect(_value(tester, entry.key), isFalse);
      expect(h.server[entry.key], isFalse);
    });

    testWidgets('${entry.key}: rolls back and says so when saving fails',
        (tester) async {
      final h = await _mount(tester, failPatch: true);
      await tester.ensureVisible(_switch(entry.key));
      await tester.tap(_switch(entry.key));
      await tester.pump();
      // Optimistic: the switch moves before the server answers.
      expect(_value(tester, entry.key), isFalse);
      h.patchGate.complete();
      await tester.pumpAndSettle();
      expect(_value(tester, entry.key), isTrue);
      expect(find.text('Couldn’t save. Try again.'), findsOneWidget);
    });
  }

  group('nearby lost pets', () {
    testWidgets('on: disclosure, then permission, then the private point',
        (tester) async {
      final h = await _mount(tester);
      await tester.ensureVisible(_switch('nearby_enabled'));
      await tester.tap(_switch('nearby_enabled'));
      await tester.pumpAndSettle();
      // The long privacy text now lives in this dialog.
      expect(find.textContaining('privately stores only your last device'),
          findsOneWidget);
      expect(find.textContaining('Profile → Settings → Notifications'),
          findsOneWidget);
      expect(h.location.requests, 0, reason: 'no permission before consent');
      await tester.tap(find.text('Allow private nearby alerts'));
      await tester.pumpAndSettle();

      expect(h.location.requests, 1);
      expect(await h.consent.read(_user), isTrue);
      final upload = h.patches.last;
      expect(upload['nearby_enabled'], isTrue);
      expect(upload['nearby_consent'], isTrue);
      expect(upload['alert_location'], isNotNull);
      expect(_value(tester, 'nearby_enabled'), isTrue);
    });

    testWidgets('declining the disclosure changes nothing', (tester) async {
      final h = await _mount(tester);
      await tester.ensureVisible(_switch('nearby_enabled'));
      await tester.tap(_switch('nearby_enabled'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Do not use my location'));
      await tester.pumpAndSettle();
      expect(h.location.requests, 0);
      expect(h.patches, isEmpty);
      expect(_value(tester, 'nearby_enabled'), isFalse);
    });

    testWidgets('permission denied: stays off and offers location settings',
        (tester) async {
      final h = await _mount(tester);
      h.location.afterRequest = AuthorizedLocationStatus.deniedForever;
      await tester.ensureVisible(_switch('nearby_enabled'));
      await tester.tap(_switch('nearby_enabled'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Allow private nearby alerts'));
      await tester.pumpAndSettle();

      expect(_value(tester, 'nearby_enabled'), isFalse);
      expect(h.patches, isEmpty);
      expect(await h.consent.read(_user), isNull);
      expect(find.text('Nearby alerts need location access.'), findsOneWidget);
      await tester.tap(find.text('Open location settings'));
      await tester.pumpAndSettle();
      expect(h.location.settings, 1);
    });

    testWidgets('off: withdraws consent and the stored point is removed',
        (tester) async {
      final h = await _mount(tester,
          locationPermission: AuthorizedLocationStatus.authorized,
          stored: {
            'nearby_enabled': true,
            'alert_location': {'latitude': 41.32, 'longitude': 69.3},
          });
      await h.consent.write(_user, true);
      expect(_value(tester, 'nearby_enabled'), isTrue);
      await tester.ensureVisible(_switch('nearby_enabled'));
      await tester.tap(_switch('nearby_enabled'));
      await tester.pumpAndSettle();

      expect(await h.consent.read(_user), isFalse);
      expect(h.patches, [
        {'nearby_enabled': false, 'expected_user_id': _user}
      ]);
      expect(h.server['alert_location'], isNull);
      expect(_value(tester, 'nearby_enabled'), isFalse);
      expect(h.location.fixes, 0, reason: 'turning off never reads GPS');
    });
  });

  testWidgets('offline screen offers retry; compact screen has no overflow',
      (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = FakeApiClient()
      ..setHandler('GET', 'notifications/preferences',
          (_) => throw StateError('offline'));
    await tester.pumpWidget(ProviderScope(overrides: [
      notificationApiProvider.overrideWithValue(NotificationApi(client)),
      devicePushAccessProvider
          .overrideWithValue(_PushAccess(DevicePushPermission.denied, true)),
      nearbyAlertsAndroidProvider.overrideWithValue(true),
    ], child: const MaterialApp(home: NotificationSettingsScreen())));
    await tester.pumpAndSettle();
    expect(find.text('Try again'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
