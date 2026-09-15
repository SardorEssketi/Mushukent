import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/core/config/app_environment.dart';

void main() {
  test('release build without API override fails fast', () {
    expect(
      () => AppEnvironment.fromValues(releaseMode: true),
      throwsA(
        isA<AppEnvironmentConfiguration>().having(
          (error) => error.message,
          'message',
          contains('MUSHUKISTAN_API_BASE_URL'),
        ),
      ),
    );
  });

  test('explicit API override is normalized', () {
    final environment = AppEnvironment.fromValues(
      apiBaseUrl: 'https://example.com',
      releaseMode: true,
    );

    expect(environment.apiBaseUri.toString(), 'https://example.com/api/v1/');
  });

  test('release web build requires Google web client ID', () {
    expect(
      () => AppEnvironment.fromValues(
        apiBaseUrl: 'https://api.mushukistan.uz',
        releaseMode: true,
        web: true,
      ),
      throwsA(
        isA<AppEnvironmentConfiguration>().having(
          (error) => error.message,
          'message',
          contains('MUSHUKISTAN_GOOGLE_CLIENT_ID'),
        ),
      ),
    );
  });

  test('release Android build requires Google server client ID', () {
    expect(
      () => AppEnvironment.fromValues(
        apiBaseUrl: 'https://api.mushukistan.uz',
        releaseMode: true,
        android: true,
      ),
      throwsA(
        isA<AppEnvironmentConfiguration>().having(
          (error) => error.message,
          'message',
          contains('MUSHUKISTAN_GOOGLE_SERVER_CLIENT_ID'),
        ),
      ),
    );
  });

  test('complete release web configuration is accepted', () {
    final environment = AppEnvironment.fromValues(
      apiBaseUrl: 'https://api.mushukistan.uz',
      googleClientId: 'web-client.apps.googleusercontent.com',
      releaseMode: true,
      web: true,
    );

    expect(
      environment.apiBaseUri.toString(),
      'https://api.mushukistan.uz/api/v1/',
    );
    expect(environment.isGoogleSignInConfigured, isTrue);
  });

  test('complete release Android configuration is accepted', () {
    final environment = AppEnvironment.fromValues(
      apiBaseUrl: 'https://api.mushukistan.uz',
      googleServerClientId: 'web-client.apps.googleusercontent.com',
      releaseMode: true,
      android: true,
    );

    expect(environment.isGoogleSignInConfigured, isTrue);
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
