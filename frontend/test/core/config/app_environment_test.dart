import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/core/config/app_environment.dart';

void main() {
  test('release build without override uses production API', () {
    final environment = AppEnvironment.fromValues(releaseMode: true);

    expect(
      environment.apiBaseUri.toString(),
      'https://api.mushukistan.uz/api/v1/',
    );
  });

  test('explicit API override is normalized', () {
    final environment = AppEnvironment.fromValues(
      apiBaseUrl: 'https://example.com',
      releaseMode: true,
    );

    expect(environment.apiBaseUri.toString(), 'https://example.com/api/v1/');
  });

  test('debug Android without override uses emulator host', () {
    final environment = AppEnvironment.fromValues(android: true);

    expect(
      environment.apiBaseUri.toString(),
      'http://10.0.2.2:8000/api/v1/',
    );
  });

  test('debug non-Android without override uses localhost', () {
    final environment = AppEnvironment.fromValues();

    expect(
      environment.apiBaseUri.toString(),
      'http://localhost:8000/api/v1/',
    );
  });

  test('invalid explicit API override still fails fast', () {
    expect(
      () => AppEnvironment.fromValues(apiBaseUrl: 'api.mushukistan.uz'),
      throwsA(isA<AppEnvironmentConfiguration>()),
    );
  });

  test('web Google sign-in uses client ID', () {
    final environment = AppEnvironment.fromValues(
      googleClientId: 'web-client.apps.googleusercontent.com',
      web: true,
    );

    expect(environment.isGoogleSignInConfigured, isTrue);
  });

  test('Android Google sign-in requires server client ID', () {
    final environment = AppEnvironment.fromValues(
      googleClientId: 'web-client.apps.googleusercontent.com',
      android: true,
    );

    expect(environment.isGoogleSignInConfigured, isFalse);
  });

  test('Android Google sign-in accepts server client ID', () {
    final environment = AppEnvironment.fromValues(
      googleServerClientId: 'web-client.apps.googleusercontent.com',
      android: true,
    );

    expect(environment.isGoogleSignInConfigured, isTrue);
  });
}
