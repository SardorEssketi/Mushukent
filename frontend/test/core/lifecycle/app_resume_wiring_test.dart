import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/app.dart';
import 'package:mushukistan_frontend/core/lifecycle/app_resume.dart';
import 'package:mushukistan_frontend/core/location/location_service.dart';
import 'package:mushukistan_frontend/core/network/api_client.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';
import 'package:mushukistan_frontend/core/onboarding/authenticated_onboarding_store.dart';
import 'package:mushukistan_frontend/features/auth/application/auth_controller.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_models.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_repository.dart';
import 'package:mushukistan_frontend/features/notifications/application/nearby_alerts.dart';
import 'package:mushukistan_frontend/features/notifications/application/notification_push.dart';

import '../../support/fakes.dart';

class _NoDevicePush extends DevicePushAccess {
  @override
  Future<DevicePushPermission> status() async => DevicePushPermission.web;
}

const _userId = '11111111-1111-4111-8111-111111111111';

/// The real app root, so lifecycle changes go through MushukistanApp's own observer.
Future<
    (
      ProviderContainer,
      FakeAuthRepository,
      FakeApiClient,
      void Function(Duration)
    )> _pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final repo = FakeAuthRepository(
    restoreResult: SessionRestoreSuccess(
      AuthSession.restored(accessToken: 'token', user: testUser()),
    ),
  );
  final client = FakeApiClient()
    ..setHandler(
        'GET',
        'feed',
        (_) => {
              'items': <Object?>[],
              'next_cursor': null,
              'limit': 30,
            })
    ..setHandler(
        'GET',
        'users/me',
        (_) => {
              'id': _userId,
              'email': 'user@example.com',
              'name': 'Sardor',
              'registered_at': '2026-07-01T10:00:00.000Z',
              'observation_count': 0,
              'total_likes_received': 0,
              'comment_count': 0,
            })
    ..setHandler('GET', 'notifications/unread-count', (_) => {'count': 0});
  var now = const Duration(hours: 1);
  final container = ProviderContainer(overrides: [
    authRepositoryProvider.overrideWithValue(repo),
    googleIdentityTokenProvider
        .overrideWithValue(FakeGoogleIdentityTokenProvider()),
    apiClientProvider.overrideWithValue(client),
    nearbyAlertsAndroidProvider.overrideWithValue(false),
    devicePushAccessProvider.overrideWithValue(_NoDevicePush()),
    authenticatedOnboardingStoreProvider.overrideWithValue(
      InMemoryAuthenticatedOnboardingStore(seenUserIds: {_userId}),
    ),
    currentLocationProvider.overrideWith(
      (ref) async => const GeoPoint(latitude: 41.2995, longitude: 69.2401),
    ),
    monotonicClockProvider.overrideWithValue(() => now),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: const MushukistanApp(),
  ));
  await tester.pumpAndSettle();
  expect(container.read(authControllerProvider).isAuthenticated, isTrue);

  void awayFor(Duration duration) {
    for (final state in const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    now += duration;
    for (final state in const [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
  }

  return (container, repo, client, awayFor);
}

int _feedRequests(FakeApiClient client) =>
    client.calls.where((call) => call.path == 'feed').length;

void main() {
  testWidgets('system lifecycle drives content refresh and session checks',
      (tester) async {
    final (container, repo, client, awayFor) = await _pumpApp(tester);
    final restores = repo.restoreCalls;
    final feeds = _feedRequests(client);

    awayFor(const Duration(minutes: 2));
    await tester.pumpAndSettle();
    expect(_feedRequests(client), feeds, reason: 'still fresh');
    expect(repo.restoreCalls, restores);

    awayFor(const Duration(minutes: 10));
    await tester.pumpAndSettle();
    expect(_feedRequests(client), feeds + 1, reason: 'content revalidated');
    expect(repo.restoreCalls, restores, reason: 'session is not due yet');

    awayFor(const Duration(minutes: 31));
    await tester.pumpAndSettle();
    expect(_feedRequests(client), feeds + 2);
    expect(repo.restoreCalls, restores + 1, reason: 'session revalidated');
    expect(container.read(authControllerProvider).isAuthenticated, isTrue);
  });

  testWidgets('a long absence while offline does not sign the user out',
      (tester) async {
    final (container, repo, _, awayFor) = await _pumpApp(tester);
    repo.restoreResult = const SessionRestoreFailure(
      message: 'Network request failed.',
      retryable: true,
    );

    awayFor(const Duration(hours: 3));
    await tester.pumpAndSettle();
    final auth = container.read(authControllerProvider);
    expect(auth.isAuthenticated, isTrue);
    expect(auth.hasUnconfirmedSession, isFalse);
  });

  testWidgets('a session rejected while away ends in the signed-out state',
      (tester) async {
    final (container, repo, _, awayFor) = await _pumpApp(tester);
    repo.restoreResult = const SessionRestoreInvalid(
      message: 'Session expired. Please sign in again.',
    );

    awayFor(const Duration(minutes: 45));
    await tester.pumpAndSettle();
    expect(
      container.read(authControllerProvider).phase,
      AuthPhase.unauthenticated,
    );
  });
}
