import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../network/mushukistan_api.dart';

final currentLocationProvider = FutureProvider<GeoPoint?>((ref) async {
  return LocationService().resolveCurrentLocation();
});

final locationServiceProvider =
    Provider<LocationService>((ref) => LocationService());

enum AuthorizedLocationStatus {
  unsupported,
  denied,
  deniedForever,
  servicesOff,
  authorized,
}

class LocationService {
  static const GeoPoint fallbackLocation = GeoPoint(
    latitude: 41.2995,
    longitude: 69.2401,
  );

  /// Permission inspection only: automatic alerts must never ask for GPS access.
  Future<AuthorizedLocationStatus> authorizedStatus() async {
    if (!kIsWeb && !Platform.isAndroid && !Platform.isIOS) {
      return AuthorizedLocationStatus.unsupported;
    }
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.deniedForever) {
      return AuthorizedLocationStatus.deniedForever;
    }
    if (permission != LocationPermission.whileInUse &&
        permission != LocationPermission.always) {
      return AuthorizedLocationStatus.denied;
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
      return AuthorizedLocationStatus.servicesOff;
    }
    return AuthorizedLocationStatus.authorized;
  }

  Future<GeoPoint?> authorizedCurrentLocation() async {
    try {
      if (await authorizedStatus() != AuthorizedLocationStatus.authorized) {
        return null;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      return GeoPoint(
          latitude: position.latitude, longitude: position.longitude);
    } catch (_) {
      return null;
    }
  }

  Future<bool> openSettings() => Geolocator.openAppSettings();

  Future<GeoPoint?> resolveCurrentLocation() async {
    try {
      if (!kIsWeb && !Platform.isAndroid && !Platform.isIOS) {
        return null;
      }

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return null;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      return GeoPoint(
        latitude: position.latitude,
        longitude: position.longitude,
      );
    } catch (_) {
      return null;
    }
  }
}
