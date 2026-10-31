import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/core/lifecycle/app_resume.dart';
import 'package:mushukistan_frontend/core/network/api_error.dart';
import 'package:mushukistan_frontend/features/auth/application/auth_controller.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_models.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_repository.dart';

import '../../support/fakes.dart';

/// Android's order when the app goes to the background and comes back.
const _leave = [
  AppLifecycleState.inactive,
  AppLifecycleState.hidden,
  AppLifecycleState.paused,
];
const _return = [
  AppLifecycleState.hidden,
  AppLifecycleState.inactive,
  AppLifecycleState.resumed,
];

void main() {
  group('AppResumeController', () {
    late Duration now;
    late AppResumeController tracker;
    late List<AppResume> events;

    setUp(() {
      now = const Duration(hours: 1);
      tracker = AppResumeController(() => now);
      events = [];
      tracker.addListener((resume) {
        if (resume != null) events.add(resume);
      }, fireImmediately: false);
    });

    void awayFor(Duration duration) {
      _leave.forEach(tracker.handleLifecycle);
      now += duration;
      _return.forEach(tracker.handleLifecycle);
    }

    test('1 minute away: one event, content still fresh', () {
      awayFor(const Duration(minutes: 1));
      expect(events, hasLength(1));
      expect(events.single.awayFor, const Duration(minutes: 1));
      expect(events.single.contentIsStale, isFalse);
      expect(events.single.sessionIsStale, isFalse);
    });

    test('5 minutes away: content is stale, the session is not', () {
      awayFor(const Duration(minutes: 5));
      expect(events.single.contentIsStale, isTrue);
      expect(events.single.sessionIsStale, isFalse);
    });

    test('30 minutes away: the session is stale too', () {
      awayFor(const Duration(minutes: 30));
      expect(events.single.contentIsStale, isTrue);
      expect(events.single.sessionIsStale, isTrue);
    });

    test('time away counts from the first moment the app was hidden', () {
      tracker.handleLifecycle(AppLifecycleState.hidden);
      now += const Duration(minutes: 3);
      tracker.handleLifecycle(AppLifecycleState.paused);
      now += const Duration(minutes: 3);
      tracker.handleLifecycle(AppLifecycleState.resumed);
      expect(events.single.awayFor, const Duration(minutes: 6));
    });

    test('inactive alone (shade, dialog, app switcher) is not leaving', () {
      tracker.handleLifecycle(AppLifecycleState.inactive);
      now += const Duration(minutes: 10);
      tracker.handleLifecycle(AppLifecycleState.resumed);
      expect(events, isEmpty);
    });

    test('repeated resume events produce one event per stay away', () {
      awayFor(const Duration(minutes: 6));
      tracker.handleLifecycle(AppLifecycleState.resumed);
      tracker.handleLifecycle(AppLifecycleState.resumed);
      expect(events, hasLength(1));

      awayFor(const Duration(minutes: 7));
      expect(events, hasLength(2));
      expect(events.last.sequence, greaterThan(events.first.sequence));
    });
  });

  group('AuthController.revalidateSession', () {
    Future<(AuthController, FakeAuthRepository)> signedIn() async {
      final repo = FakeAuthRepository(
        restoreResult: SessionRestoreSuccess(
          AuthSession.restored(accessToken: 'token', user: testUser()),
        ),
      );
      final controller =
          AuthController(repo, FakeGoogleIdentityTokenProvider());
      await controller.restoreSession();
      expect(controller.state.isAuthenticated, isTrue);
      return (controller, repo);
    }

    test('a confirmed session stays signed in, with a fresh profile', () async {
      final (controller, repo) = await signedIn();
      final calls = repo.restoreCalls;
      repo.restoreResult = SessionRestoreSuccess(AuthSession.restored(
        accessToken: 'token',
        user: testUser(name: 'Renamed'),
      ));
      await controller.revalidateSession();
      expect(repo.restoreCalls, calls + 1);
      expect(controller.state.isAuthenticated, isTrue);
      expect(controller.state.user?.name, 'Renamed');
    });

    test('a rejected session ends in the signed-out state', () async {
      final (controller, repo) = await signedIn();
      repo.restoreResult = const SessionRestoreInvalid(
        message: 'Session expired. Please sign in again.',
      );
      await controller.revalidateSession();
      expect(controller.state.phase, AuthPhase.unauthenticated);
      expect(controller.state.message, contains('expired'));
    });

    test('a temporary network failure keeps the user signed in', () async {
      final (controller, repo) = await signedIn();
      repo.restoreResult = const SessionRestoreFailure(
        message: 'Network request failed.',
        retryable: true,
      );
      await controller.revalidateSession();
      expect(controller.state.isAuthenticated, isTrue);
      expect(controller.state.hasUnconfirmedSession, isFalse);

      repo.restoreError = const MushukistanApiException(
        kind: ApiFailureKind.network,
        code: 'NETWORK_ERROR',
        message: 'offline',
      );
      await controller.revalidateSession();
      expect(controller.state.isAuthenticated, isTrue);
    });

    test('credentials that changed underneath are not treated as a rejection',
        () async {
      final (controller, repo) = await signedIn();
      repo.restoreResult = const SessionRestoreMissing();
      await controller.revalidateSession();
      expect(controller.state.isAuthenticated, isTrue);
    });

    test('repeated requests share one check', () async {
      final (controller, repo) = await signedIn();
      final calls = repo.restoreCalls;
      final pending = Completer<SessionRestoreResult>();
      repo.restoreCompleter = pending;
      final first = controller.revalidateSession();
      final second = controller.revalidateSession();
      expect(repo.restoreCalls, calls + 1);
      pending.complete(SessionRestoreSuccess(
        AuthSession.restored(accessToken: 'token', user: testUser()),
      ));
      await Future.wait([first, second]);
      expect(controller.state.isAuthenticated, isTrue);
    });

    test('does nothing for a guest or while a restore is running', () async {
      final guestRepo = FakeAuthRepository();
      final guest =
          AuthController(guestRepo, FakeGoogleIdentityTokenProvider());
      await guest.restoreSession();
      final guestCalls = guestRepo.restoreCalls;
      await guest.revalidateSession();
      expect(guestRepo.restoreCalls, guestCalls);

      final slowRepo = FakeAuthRepository()
        ..restoreCompleter = Completer<SessionRestoreResult>();
      final restoring =
          AuthController(slowRepo, FakeGoogleIdentityTokenProvider());
      await Future<void>.delayed(Duration.zero);
      await restoring.revalidateSession();
      expect(slowRepo.restoreCalls, 1);
      restoring.dispose();
    });

    test('a logout during the check wins', () async {
      final (controller, repo) = await signedIn();
      final pending = Completer<SessionRestoreResult>();
      repo.restoreCompleter = pending;
      final check = controller.revalidateSession();
      await controller.logout();
      pending.complete(SessionRestoreSuccess(
        AuthSession.restored(accessToken: 'token', user: testUser()),
      ));
      await check;
      expect(controller.state.phase, AuthPhase.unauthenticated);
    });
  });
}
