// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:mushukistan_frontend/core/config/app_environment.dart';
import 'package:mushukistan_frontend/features/auth/infrastructure/google_sign_in_service.dart';

class _FakeGooglePlatform extends GoogleSignInPlatform {
  final initGate = Completer<void>();
  final firstAuthenticationGate = Completer<AuthenticationResults>();
  int initCalls = 0;
  int authenticationCalls = 0;

  @override
  Future<void> init(InitParameters params) {
    initCalls += 1;
    expect(params.serverClientId, 'test-web-client-id');
    return initGate.future;
  }

  @override
  bool supportsAuthenticate() => true;

  @override
  Future<AuthenticationResults> authenticate(AuthenticateParameters params) {
    authenticationCalls += 1;
    if (authenticationCalls == 1) return firstAuthenticationGate.future;
    return Future.value(_result);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _result = AuthenticationResults(
  user: GoogleSignInUserData(email: 'test@example.com', id: 'test-subject'),
  authenticationTokens: AuthenticationTokenData(idToken: 'test-id-token'),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('concurrent taps initialize once and only start one Google login',
      () async {
    final priorPlatform = GoogleSignInPlatform.instance;
    final platform = _FakeGooglePlatform();
    GoogleSignInPlatform.instance = platform;
    addTearDown(() => GoogleSignInPlatform.instance = priorPlatform);
    final service = GoogleSignInService(AppEnvironment(
      apiBaseUri: Uri.parse('https://api.example.com/api/v1/'),
      googleServerClientId: 'test-web-client-id',
      isAndroid: true,
    ));

    final first = service.authenticate();
    await expectLater(
      service.authenticate(),
      throwsA(isA<GoogleSignInFlowException>()),
    );
    expect(platform.initCalls, 1);
    platform.initGate.complete();
    await Future<void>.delayed(Duration.zero);
    expect(platform.authenticationCalls, 1);
    platform.firstAuthenticationGate.complete(_result);
    expect(await first, 'test-id-token');

    // A later login, including after app logout, can reuse initialization.
    expect(await service.authenticate(), 'test-id-token');
    expect(platform.initCalls, 1);
    expect(platform.authenticationCalls, 2);
  });
}
