import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AppEnvironmentConfiguration implements Exception {
  AppEnvironmentConfiguration(this.message);

  final String message;

  @override
  String toString() => message;
}

class AppEnvironment {
  AppEnvironment({
    required this.apiBaseUri,
    this.requestTimeout = const Duration(seconds: 15),
    this.googleClientId,
    this.googleServerClientId,
    this.isWeb = kIsWeb,
    this.isAndroid = false,
  });

  final Uri apiBaseUri;
  final Duration requestTimeout;
  final String? googleClientId;
  final String? googleServerClientId;
  final bool isWeb;
  final bool isAndroid;

  static const productionApiBaseUrl = 'https://api.mushukistan.uz';

  bool get isGoogleSignInConfigured => isWeb
      ? googleClientId != null && googleClientId!.isNotEmpty
      : isAndroid
          ? googleServerClientId != null && googleServerClientId!.isNotEmpty
          : (googleClientId != null && googleClientId!.isNotEmpty) ||
              (googleServerClientId != null &&
                  googleServerClientId!.isNotEmpty);

  static AppEnvironment fromBuildEnvironment() {
    return fromValues(
      apiBaseUrl:
          const String.fromEnvironment('MUSHUKISTAN_API_BASE_URL').trim(),
      googleClientId:
          const String.fromEnvironment('MUSHUKISTAN_GOOGLE_CLIENT_ID').trim(),
      googleServerClientId:
          const String.fromEnvironment('MUSHUKISTAN_GOOGLE_SERVER_CLIENT_ID')
              .trim(),
      releaseMode: kReleaseMode,
      web: kIsWeb,
      android: !kIsWeb && Platform.isAndroid,
    );
  }

  @visibleForTesting
  static AppEnvironment fromValues({
    String apiBaseUrl = '',
    String googleClientId = '',
    String googleServerClientId = '',
    bool releaseMode = false,
    bool web = false,
    bool android = false,
  }) {
    final override = apiBaseUrl.trim();
    final normalizedGoogleClientId = googleClientId.trim();
    final normalizedGoogleServerClientId = googleServerClientId.trim();
    if (override.isNotEmpty) {
      return AppEnvironment(
        apiBaseUri: _normalizeApiBaseUri(override),
        googleClientId:
            normalizedGoogleClientId.isEmpty ? null : normalizedGoogleClientId,
        googleServerClientId: normalizedGoogleServerClientId.isEmpty
            ? null
            : normalizedGoogleServerClientId,
        isWeb: web,
        isAndroid: android,
      );
    }

    if (releaseMode) {
      return AppEnvironment(
        apiBaseUri: _normalizeApiBaseUri(productionApiBaseUrl),
        googleClientId:
            normalizedGoogleClientId.isEmpty ? null : normalizedGoogleClientId,
        googleServerClientId: normalizedGoogleServerClientId.isEmpty
            ? null
            : normalizedGoogleServerClientId,
        isWeb: web,
        isAndroid: android,
      );
    }

    final fallback =
        !web && android ? 'http://10.0.2.2:8000' : 'http://localhost:8000';
    return AppEnvironment(
      apiBaseUri: _normalizeApiBaseUri(fallback),
      googleClientId:
          normalizedGoogleClientId.isEmpty ? null : normalizedGoogleClientId,
      googleServerClientId: normalizedGoogleServerClientId.isEmpty
          ? null
          : normalizedGoogleServerClientId,
      isWeb: web,
      isAndroid: android,
    );
  }
}

final appEnvironmentProvider = Provider<AppEnvironment>((ref) {
  return AppEnvironment.fromBuildEnvironment();
});

Uri _normalizeApiBaseUri(String rawBaseUrl) {
  final parsed = Uri.tryParse(rawBaseUrl.trim());
  if (parsed == null ||
      !parsed.hasScheme ||
      (parsed.scheme != 'http' && parsed.scheme != 'https')) {
    throw AppEnvironmentConfiguration(
        'Invalid MUSHUKISTAN_API_BASE_URL value.');
  }

  final normalizedPath = _normalizeApiPath(parsed.path);
  return parsed.replace(path: normalizedPath);
}

String _normalizeApiPath(String path) {
  final trimmed = path.trim();
  if (trimmed.isEmpty || trimmed == '/') {
    return '/api/v1/';
  }
  if (trimmed.endsWith('/api/v1/')) {
    return trimmed;
  }
  if (trimmed.endsWith('/api/v1')) {
    return '$trimmed/';
  }
  if (trimmed.endsWith('/')) {
    return '${trimmed}api/v1/';
  }
  return '$trimmed/api/v1/';
}
