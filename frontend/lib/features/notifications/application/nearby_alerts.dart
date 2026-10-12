import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/location/location_service.dart';
import '../../auth/application/auth_controller.dart';
import '../data/notification_api.dart';

final nearbyConsentStoreProvider = Provider((ref) => NearbyConsentStore());
final nearbyAlertsAndroidProvider = Provider(
    (ref) => !kIsWeb && defaultTargetPlatform == TargetPlatform.android);

final nearbyAlertsProvider = ChangeNotifierProvider((ref) => NearbyAlerts(
      api: ref.read(notificationApiProvider),
      location: ref.read(locationServiceProvider),
      consent: ref.read(nearbyConsentStoreProvider),
      android: ref.read(nearbyAlertsAndroidProvider),
      currentUser: () => ref.read(currentUserProvider)?.id,
    ));

class NearbyConsentStore {
  final _storage = const FlutterSecureStorage();
  Future<bool?> read(String user) async {
    final value = await _storage.read(key: 'nearby_alerts_consent_v1_$user');
    return value == null ? null : value == 'granted';
  }

  Future<void> write(String user, bool granted) => _storage.write(
      key: 'nearby_alerts_consent_v1_$user',
      value: granted ? 'granted' : 'declined');

  Future<bool> pushAsked(String user) async =>
      await _storage.read(key: 'push_disclosure_v1_$user') == 'shown';
  Future<void> markPushAsked(String user) =>
      _storage.write(key: 'push_disclosure_v1_$user', value: 'shown');
}

enum NearbyAlertStatus {
  unsupported,
  consentRequired,
  permissionMissing,
  locationUnavailable,
  available,
  syncFailed,
}

/// One foreground fix on authenticated launch/resume, never a location stream.
/// No coordinates are cached on disk, logged, or attached to public profiles.
class NearbyAlerts extends ChangeNotifier {
  NearbyAlerts(
      {required this.api,
      required this.location,
      required this.consent,
      required this.android,
      required this.currentUser});
  final NotificationApi api;
  final LocationService location;
  final NearbyConsentStore consent;
  final bool android;
  final String? Function() currentUser;
  NearbyAlertStatus status = NearbyAlertStatus.unsupported;
  AuthorizedLocationStatus permission = AuthorizedLocationStatus.unsupported;
  String? _user;
  int _generation = 0;
  bool _foreground = true;
  bool _disposed = false;
  Future<void>? _flight;
  int? _flightGeneration;

  void activate(String? user) {
    if (_user == user) return;
    _user = user;
    _generation++;
    status = NearbyAlertStatus.unsupported;
  }

  void foreground(bool value) {
    _foreground = value;
    if (!value) _generation++; // Discard a fix arriving after app pause.
  }

  bool _current(String user, int generation) =>
      !_disposed &&
      _foreground &&
      _user == user &&
      currentUser() == user &&
      _generation == generation;

  void _status(NearbyAlertStatus value) {
    if (_disposed) return;
    status = value;
    notifyListeners();
  }

  Future<void> _clear(String user, int generation) async {
    if (!_current(user, generation)) return;
    await api
        .updatePreferences({'nearby_enabled': false, 'expected_user_id': user});
  }

  Future<void> sync(String user, {Future<bool> Function()? disclose}) async {
    if (!android) return; // Browser activity must not clear an Android point.
    activate(user);
    // Coalesce overlapping resumes; account changes wait for the old request.
    if (_flight != null) {
      final waitingGeneration = _flightGeneration;
      await _flight;
      if (_user != user || currentUser() != user) return;
      if (_generation == waitingGeneration) return;
    }
    if (!_foreground || _disposed) return;
    final generation = _generation;
    final operation = _sync(user, generation, disclose);
    _flight = operation;
    _flightGeneration = generation;
    try {
      await operation;
    } finally {
      if (identical(_flight, operation)) _flight = null;
    }
  }

  Future<void> _sync(
      String user, int generation, Future<bool> Function()? disclose) async {
    try {
      permission = await location.authorizedStatus();
      if (!_current(user, generation)) return;
      var granted = await consent.read(user);
      if (!_current(user, generation)) return;
      if (granted != true ||
          permission != AuthorizedLocationStatus.authorized) {
        // Includes legacy manually selected points, denied/revoked permissions,
        // disabled GPS, and withdrawn consent. Retry on the next online resume.
        await _clear(user, generation);
        if (!_current(user, generation)) return;
      }
      if (granted == null && disclose != null) {
        granted = await disclose();
        if (!_current(user, generation)) return;
        await consent.write(user, granted);
      }
      if (granted != true) {
        _status(NearbyAlertStatus.consentRequired);
        return;
      }
      if (permission != AuthorizedLocationStatus.authorized) {
        _status(NearbyAlertStatus.permissionMissing);
        return;
      }
      final point = await location.authorizedCurrentLocation();
      if (!_current(user, generation)) return;
      permission = await location.authorizedStatus();
      if (!_current(user, generation)) return;
      if (permission != AuthorizedLocationStatus.authorized) {
        await _clear(user, generation);
        if (_current(user, generation)) {
          _status(NearbyAlertStatus.permissionMissing);
        }
        return;
      }
      if (point == null ||
          !point.latitude.isFinite ||
          !point.longitude.isFinite ||
          point.latitude.abs() > 90 ||
          point.longitude.abs() > 180) {
        await _clear(user, generation);
        if (_current(user, generation)) {
          _status(NearbyAlertStatus.locationUnavailable);
        }
        return;
      }
      // Recheck after GPS and storage awaits so logout/withdrawal cannot upload.
      final stillGranted = await consent.read(user);
      if (!_current(user, generation) || stillGranted != true) return;
      final updated = await api.updatePreferences({
        'expected_user_id': user,
        'nearby_enabled': true,
        'nearby_consent': true,
        'alert_location': {
          'latitude': point.latitude,
          'longitude': point.longitude
        },
      });
      if (_current(user, generation)) {
        _status(updated.nearbyEnabled && updated.alertLocation != null
            ? NearbyAlertStatus.available
            : NearbyAlertStatus.syncFailed);
      }
    } catch (_) {
      if (_current(user, generation)) {
        try {
          await _clear(user, generation);
        } catch (_) {
          // A failed offline deletion retries on the next foreground sync.
        }
        if (_current(user, generation)) _status(NearbyAlertStatus.syncFailed);
      }
    }
  }

  Future<void> setConsent(String user, bool granted) async {
    if (currentUser() != user) return;
    activate(user);
    _generation++; // Invalidate an in-flight GPS fix before persisting withdrawal.
    await consent.write(user, granted);
    await sync(user);
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
