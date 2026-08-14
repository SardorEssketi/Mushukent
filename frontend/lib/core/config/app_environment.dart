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
  });

  final Uri apiBaseUri;
  final Duration requestTimeout;
  final String? googleClientId;
  final String? googleServerClientId;

  bool get isGoogleSignInConfigured => kIsWeb
      ? googleClientId != null && googleClientId!.isNotEmpty
      : (googleClientId != null && googleClientId!.isNotEmpty) ||
          (googleServerClientId != null && googleServerClientId!.isNotEmpty);

  static AppEnvironment fromBuildEnvironment() {
    final override =
        const String.fromEnvironment('MUSHUKISTAN_API_BASE_URL').trim();
    final googleClientId =
        const String.fromEnvironment('MUSHUKISTAN_GOOGLE_CLIENT_ID').trim();
    final googleServerClientId =
        const String.fromEnvironment('MUSHUKISTAN_GOOGLE_SERVER_CLIENT_ID')
            .trim();
    if (override.isNotEmpty) {
      return AppEnvironment(
        apiBaseUri: _normalizeApiBaseUri(override),
        googleClientId: googleClientId.isEmpty ? null : googleClientId,
        googleServerClientId:
            googleServerClientId.isEmpty ? null : googleServerClientId,
      );
    }
    if (kReleaseMode) {
      throw AppEnvironmentConfiguration(
        'Missing MUSHUKISTAN_API_BASE_URL build configuration.',
      );
    }
    final fallback = !kIsWeb && Platform.isAndroid
        ? 'http://10.0.2.2:8000'
        : 'http://localhost:8000';
    return AppEnvironment(
      apiBaseUri: _normalizeApiBaseUri(fallback),
      googleClientId: googleClientId.isEmpty ? null : googleClientId,
      googleServerClientId:
          googleServerClientId.isEmpty ? null : googleServerClientId,
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
