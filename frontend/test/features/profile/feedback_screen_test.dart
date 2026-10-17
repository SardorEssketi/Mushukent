import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mushukistan_frontend/core/localization/language_controller.dart';
import 'package:mushukistan_frontend/core/network/api_client.dart';
import 'package:mushukistan_frontend/core/network/api_error.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';
import 'package:mushukistan_frontend/features/auth/application/auth_controller.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_models.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_repository.dart';
import 'package:mushukistan_frontend/features/profile/presentation/screens/feedback_screen.dart';
import 'package:mushukistan_frontend/features/profile/presentation/screens/profile_screen.dart';

import '../../support/fakes.dart';

const _validMessage = 'The map freezes when switching between tabs.';

void main() {
  Future<(FakeApiClient, GoRouter)> mount(
    WidgetTester tester, {
    Size size = const Size(390, 850),
    AppLanguage? language,
    ThemeData? theme,
    FutureOr<Object?> Function(ApiCall call)? handler,
    bool openFeedback = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final client = FakeApiClient();
    client.setHandler('POST', 'feedback', handler ?? (_) => null);
    final container = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(client),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(
        restoreResult: SessionRestoreSuccess(
          AuthSession.restored(accessToken: 'token', user: testUser()),
        ),
      )),
      googleIdentityTokenProvider.overrideWithValue(
        FakeGoogleIdentityTokenProvider(),
      ),
      profileMeProvider.overrideWith((ref) async => UserProfileData(
            id: testUser().id,
            email: 'owner@example.com',
            registeredAt: DateTime.utc(2026, 7, 1),
            observationCount: 1,
            totalLikesReceived: 2,
            commentCount: 3,
            name: 'Sardor',
          )),
      if (language != null) appLanguageProvider.overrideWith((ref) => language),
    ]);
    await container.read(authControllerProvider.notifier).restoreSession();
    final router = GoRouter(initialLocation: '/profile', routes: [
      GoRoute(
        path: '/profile',
        builder: (_, __) => const ProfileScreen(),
        routes: [
          GoRoute(
            path: 'feedback',
            builder: (_, __) => const FeedbackScreen(),
          ),
          GoRoute(
            path: 'settings',
            builder: (_, __) => const Scaffold(body: Text('Settings route')),
          ),
        ],
      ),
    ]);
    addTearDown(container.dispose);
    addTearDown(router.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router, theme: theme),
    ));
    await tester.pumpAndSettle();
    if (openFeedback) {
      await tester.scrollUntilVisible(find.text(_entryTitle(language)), 200);
      await tester.ensureVisible(find.text(_entryTitle(language)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_entryTitle(language)));
      await tester.pumpAndSettle();
    }
    return (client, router);
  }

  Future<void> fillAndSelect(
    WidgetTester tester, {
    String category = 'bug',
    String message = _validMessage,
  }) async {
    await tester.tap(find.byKey(ValueKey('feedback-category-$category')));
    await tester.pump();
    await tester.enterText(
        find.byKey(const ValueKey('feedback-message')), message);
    await tester.pump();
  }

  testWidgets('Profile lists Feedback with a Beta badge near Settings',
      (tester) async {
    await mount(tester, openFeedback: false);
    expect(find.text('Feedback'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.byIcon(Icons.rate_review_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Feedback entry opens the form with three categories',
      (tester) async {
    await mount(tester);
    expect(find.text('Help improve Mushukistan'), findsOneWidget);
    expect(find.text('Bug report'), findsOneWidget);
    expect(find.text('Feature suggestion'), findsOneWidget);
    expect(find.text('Other feedback'), findsOneWidget);
    expect(find.byKey(const ValueKey('feedback-message')), findsOneWidget);
  });

  testWidgets('category selection is exclusive', (tester) async {
    await mount(tester);
    ChoiceChip chip(String key) => tester
        .widget<ChoiceChip>(find.byKey(ValueKey('feedback-category-$key')));
    await tester.tap(find.byKey(const ValueKey('feedback-category-bug')));
    await tester.pump();
    expect(chip('bug').selected, isTrue);
    await tester
        .tap(find.byKey(const ValueKey('feedback-category-suggestion')));
    await tester.pump();
    expect(chip('bug').selected, isFalse);
    expect(chip('suggestion').selected, isTrue);
  });

  testWidgets('validation blocks empty, short and category-less submissions',
      (tester) async {
    final (client, _) = await mount(tester);

    await tester.tap(find.byKey(const ValueKey('feedback-send')));
    await tester.pump();
    expect(find.text('Please write a message.'), findsOneWidget);
    expect(find.text('Choose a category.'), findsOneWidget);

    await fillAndSelect(tester, message: 'too short');
    expect(find.text('Please write at least 10 characters.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('feedback-send')));
    await tester.pump();
    expect(client.calls.where((c) => c.path == 'feedback'), isEmpty);
  });

  testWidgets('message field caps input at 2,000 characters', (tester) async {
    await mount(tester);
    await tester.enterText(
        find.byKey(const ValueKey('feedback-message')), 'x' * 2500);
    await tester.pump();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text.length, feedbackMaxLength);
  });

  testWidgets('successful submission posts trimmed payload and thanks the user',
      (tester) async {
    final (client, _) = await mount(tester);
    await fillAndSelect(tester,
        category: 'suggestion', message: '  $_validMessage  ');
    await tester.tap(find.byKey(const ValueKey('feedback-send')));
    await tester.pumpAndSettle();

    final call = client.calls.singleWhere((c) => c.path == 'feedback');
    final body = call.body! as Map<String, Object?>;
    expect(body['category'], 'suggestion');
    expect(body['message'], _validMessage);
    expect(body['platform'], isIn(['web', 'android']));
    expect(find.text('Thank you! Your feedback helps us improve Mushukistan.'),
        findsOneWidget);
    expect(find.byKey(const ValueKey('feedback-message')), findsNothing);

    await tester.tap(find.text('Back to Profile'));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('shows progress and ignores repeat taps while sending',
      (tester) async {
    final gate = Completer<Object?>();
    final (client, _) = await mount(tester, handler: (_) => gate.future);
    await fillAndSelect(tester);
    await tester.tap(find.byKey(const ValueKey('feedback-send')));
    await tester.pump();

    expect(find.text('Sending…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final button = tester
        .widget<FilledButton>(find.byKey(const ValueKey('feedback-send')));
    expect(button.onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('feedback-send')),
        warnIfMissed: false);
    await tester.pump();
    expect(client.calls.where((c) => c.path == 'feedback'), hasLength(1));

    gate.complete(null);
    await tester.pumpAndSettle();
    expect(client.calls.where((c) => c.path == 'feedback'), hasLength(1));
  });

  Future<void> expectFailureKeepsDraft(
    WidgetTester tester,
    MushukistanApiException error,
    String expectedMessage,
  ) async {
    await mount(tester, handler: (_) => throw error);
    await fillAndSelect(tester);
    await tester.tap(find.byKey(const ValueKey('feedback-send')));
    await tester.pumpAndSettle();

    expect(find.textContaining(expectedMessage), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, _validMessage);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('feedback-send')))
          .onPressed,
      isNotNull,
    );
  }

  testWidgets('network failure keeps the draft and allows retry',
      (tester) async {
    await expectFailureKeepsDraft(
      tester,
      const MushukistanApiException(
        kind: ApiFailureKind.network,
        code: 'NETWORK_ERROR',
        message: 'Network request failed.',
      ),
      'Could not reach Mushukistan',
    );
  });

  testWidgets('rate limit response explains the wait', (tester) async {
    await expectFailureKeepsDraft(
      tester,
      const MushukistanApiException(
        kind: ApiFailureKind.unknown,
        code: 'FEEDBACK_RATE_LIMITED',
        message: 'slow down',
        statusCode: 429,
      ),
      'sent several messages recently',
    );
  });

  testWidgets('expired session asks the user to sign in again', (tester) async {
    await expectFailureKeepsDraft(
      tester,
      const MushukistanApiException(
        kind: ApiFailureKind.unauthorized,
        code: 'UNAUTHORIZED',
        message: 'expired',
        statusCode: 401,
      ),
      'session has expired',
    );
  });

  testWidgets('leaving with an unfinished draft asks for confirmation',
      (tester) async {
    await mount(tester);
    await tester.enterText(
        find.byKey(const ValueKey('feedback-message')), 'half written');
    await tester.pump();

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Keep editing'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('feedback-message')), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Discard changes'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('feedback-message')), findsNothing);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('an untouched form closes without a prompt', (tester) async {
    await mount(tester);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byKey(const ValueKey('feedback-message')), findsNothing);
  });

  testWidgets('Russian and Uzbek copy are used', (tester) async {
    await mount(tester, language: AppLanguage.russian);
    expect(find.text('Помогите улучшить Mushukistan'), findsOneWidget);
    expect(find.text('Сообщить об ошибке'), findsOneWidget);
    expect(find.text('Отправить'), findsOneWidget);
  });

  testWidgets('Uzbek profile entry uses Fikr-mulohaza', (tester) async {
    await mount(tester, language: AppLanguage.uzbek, openFeedback: false);
    expect(find.text('Fikr-mulohaza'), findsOneWidget);
  });

  for (final (label, size, dark) in [
    ('narrow phone', const Size(320, 640), false),
    ('phone dark', const Size(390, 850), true),
    ('tablet', const Size(820, 1180), false),
    ('desktop dark', const Size(1440, 900), true),
  ]) {
    testWidgets('layout has no overflow: $label', (tester) async {
      await mount(
        tester,
        size: size,
        language: AppLanguage.russian,
        theme: dark ? ThemeData.dark(useMaterial3: true) : null,
      );
      expect(tester.takeException(), isNull);
      // The send button must be reachable by scrolling on the smallest screens.
      // Jump the page's own scroll view to its end (the multiline field has
      // a scrollable of its own, so a drag could land on it instead).
      final page = tester.state<ScrollableState>(find
          .descendant(
            of: find.byType(FeedbackScreen),
            matching: find.byType(Scrollable),
          )
          .first);
      page.position.jumpTo(page.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('feedback-send')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

String _entryTitle(AppLanguage? language) => switch (language) {
      AppLanguage.russian => 'Обратная связь',
      AppLanguage.uzbek => 'Fikr-mulohaza',
      _ => 'Feedback',
    };
