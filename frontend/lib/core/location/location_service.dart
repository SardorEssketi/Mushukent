import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../network/mushukistan_api.dart';

final currentLocationProvider = FutureProvider<GeoPoint>((ref) async {
  return LocationService().resolveCurrentLocation();
});

class LocationService {
  static const GeoPoint fallbackLocation = GeoPoint(
    latitude: 41.2995,
    longitude: 69.2401,
  );

  Future<GeoPoint> resolveCurrentLocation() async {
    try {
      if (!kIsWeb && !Platform.isAndroid && !Platform.isIOS) {
        return fallbackLocation;
      }

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return fallbackLocation;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return fallbackLocation;
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
      return fallbackLocation;
    }
  }
}
