import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/core/location/location_service.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';
import 'package:mushukistan_frontend/features/notifications/application/nearby_alerts.dart';
import 'package:mushukistan_frontend/features/notifications/data/notification_api.dart';

import 'support/fakes.dart';

class MemoryConsent extends NearbyConsentStore {
  final choices = <String, bool>{};
  @override
  Future<bool?> read(String user) async => choices[user];
  @override
  Future<void> write(String user, bool granted) async {
    choices[user] = granted;
  }
}

class AuthorizedLocationFake extends LocationService {
  AuthorizedLocationStatus permission = AuthorizedLocationStatus.authorized;
  GeoPoint? point = const GeoPoint(latitude: 41.32, longitude: 69.3);
  Completer<GeoPoint?>? pending;
  int fixes = 0;
  int permissionRequests = 0;
  int settings = 0;
  @override
  Future<AuthorizedLocationStatus> authorizedStatus() async => permission;
  @override
  Future<GeoPoint?> authorizedCurrentLocation() async {
    fixes++;
    return pending == null ? point : pending!.future;
  }

  @override
  Future<GeoPoint?> resolveCurrentLocation() async {
    permissionRequests++;
    throw StateError('Automatic alerts must not request permission');
  }

  @override
  Future<bool> openSettings() async {
    settings++;
    return true;
  }
}

class NearbyApiFake extends NotificationApi {
  NearbyApiFake() : super(FakeApiClient());
  final patches = <Map<String, Object?>>[];
  bool offline = false;
  @override
  Future<NotificationPreferences> updatePreferences(
      Map<String, Object?> patch) async {
    patches.add(patch);
    if (offline) throw StateError('offline');
    return NotificationPreferences(
        pushComments: true,
        pushReplies: true,
        pushFollowups: true,
        inactivityEnabled: true,
        pushAvailable: true,
        nearbyEnabled: patch['nearby_enabled'] == true,
        alertLocation: patch['alert_location'] == null
            ? null
            : AlertPoint.fromJson(patch['alert_location']));
  }
}

Future<void> flushAsync() => Future<void>.delayed(Duration.zero);

void main() {
  late MemoryConsent consent;
  late AuthorizedLocationFake location;
  late NearbyApiFake api;
  late NearbyAlerts alerts;
  String? current;
  setUp(() {
    current = 'owner';
    consent = MemoryConsent()..choices['owner'] = true;
    location = AuthorizedLocationFake();
    api = NearbyApiFake();
    alerts = NearbyAlerts(
        api: api,
        location: location,
        consent: consent,
        android: true,
        currentUser: () => current);
  });
  tearDown(() => alerts.dispose());

  test('foreground authorized fix uploads automatically; next resume refreshes',
      () async {
    await alerts.sync('owner');
    expect(api.patches.single['nearby_consent'], true);
    expect(api.patches.single['alert_location'],
        {'latitude': 41.32, 'longitude': 69.3});
    expect(alerts.status, NearbyAlertStatus.available);
    alerts.foreground(false);
    alerts.foreground(true);
    await alerts.sync('owner');
    expect(location.fixes, 2);
    expect(location.permissionRequests, 0);
  });

  test(
      'OS permission alone never grants storage consent; legacy point is cleared first',
      () async {
    consent.choices.clear();
    int prompts = 0;
    await alerts.sync('owner', disclose: () async {
      prompts++;
      expect(api.patches.single,
          {'nearby_enabled': false, 'expected_user_id': 'owner'});
      expect(location.fixes, 0);
      return true;
    });
    await alerts.sync('owner', disclose: () async {
      prompts++;
      return true;
    });
    expect(prompts, 1);
    expect(consent.choices['owner'], true);
    expect(api.patches.last['nearby_enabled'], true);
  });

  test('declined consent removes point without fetching GPS or prompting again',
      () async {
    consent.choices['owner'] = false;
    await alerts.sync('owner',
        disclose: () async => throw StateError('Unexpected prompt'));
    expect(api.patches.single,
        {'nearby_enabled': false, 'expected_user_id': 'owner'});
    expect(location.fixes, 0);
    expect(alerts.status, NearbyAlertStatus.consentRequired);
  });

  for (final permission in [
    AuthorizedLocationStatus.denied,
    AuthorizedLocationStatus.deniedForever,
    AuthorizedLocationStatus.servicesOff
  ]) {
    test('$permission clears point without asking for access', () async {
      location.permission = permission;
      await alerts.sync('owner');
      expect(api.patches.single,
          {'nearby_enabled': false, 'expected_user_id': 'owner'});
      expect(location.fixes, 0);
      expect(location.permissionRequests, 0);
      expect(alerts.status, NearbyAlertStatus.permissionMissing);
    });
  }

  test('permission revoked while GPS is pending discards fix and clears point',
      () async {
    location.pending = Completer();
    final sync = alerts.sync('owner');
    await flushAsync();
    location.permission = AuthorizedLocationStatus.denied;
    location.pending!.complete(location.point);
    await sync;
    expect(api.patches.single,
        {'nearby_enabled': false, 'expected_user_id': 'owner'});
  });

  for (final point in [
    null,
    const GeoPoint(latitude: double.nan, longitude: 69),
    const GeoPoint(latitude: 91, longitude: 69)
  ]) {
    test('invalid/missing fix $point clears location; no Tashkent fallback',
        () async {
      location.point = point;
      await alerts.sync('owner');
      expect(api.patches.single,
          {'nearby_enabled': false, 'expected_user_id': 'owner'});
      expect(alerts.status, NearbyAlertStatus.locationUnavailable);
    });
  }

  test('logout cancels a pending upload', () async {
    location.pending = Completer();
    final sync = alerts.sync('owner');
    await flushAsync();
    current = null;
    alerts.activate(null);
    location.pending!.complete(location.point);
    await sync;
    expect(api.patches, isEmpty);
  });

  test('backgrounding discards pending GPS fix', () async {
    location.pending = Completer();
    final sync = alerts.sync('owner');
    await flushAsync();
    alerts.foreground(false);
    location.pending!.complete(location.point);
    await sync;
    expect(api.patches, isEmpty);
  });

  test('withdrawal cancels pending upload and clears server point', () async {
    location.pending = Completer();
    final sync = alerts.sync('owner');
    await flushAsync();
    final withdrawal = alerts.setConsent('owner', false);
    await flushAsync();
    location.pending!.complete(location.point);
    await Future.wait([sync, withdrawal]);
    expect(consent.choices['owner'], false);
    expect(api.patches.single,
        {'nearby_enabled': false, 'expected_user_id': 'owner'});
  });

  test('overlapping lifecycle calls coalesce into one fix', () async {
    location.pending = Completer();
    final first = alerts.sync('owner');
    await flushAsync();
    final second = alerts.sync('owner');
    location.pending!.complete(location.point);
    await Future.wait([first, second]);
    expect(location.fixes, 1);
    expect(api.patches.length, 1);
  });

  test(
      'offline withdrawal stays refused locally and retries clearing on resume',
      () async {
    api.offline = true;
    await alerts.setConsent('owner', false);
    expect(alerts.status, NearbyAlertStatus.syncFailed);
    api.offline = false;
    await alerts.sync('owner');
    expect(
        api.patches.every((patch) => patch['nearby_enabled'] == false), true);
    expect(location.fixes, 0);
  });

  test('browser lifecycle never replaces or clears an Android alert point',
      () async {
    final web = NearbyAlerts(
        api: api,
        location: location,
        consent: consent,
        android: false,
        currentUser: () => current);
    await web.sync('owner');
    expect(api.patches, isEmpty);
    expect(location.fixes, 0);
    web.dispose();
  });
}
