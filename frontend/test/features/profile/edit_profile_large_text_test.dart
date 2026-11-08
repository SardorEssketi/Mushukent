// AUTH-209: the Uzbekistan phone-format guidance stays complete at large text
// sizes. These tests check the rendered paragraph (not only its semantics):
// it must not be cut off with an ellipsis or a line limit.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mushukistan_frontend/core/localization/app_strings.dart';
import 'package:mushukistan_frontend/core/localization/language_controller.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';
import 'package:mushukistan_frontend/features/profile/presentation/screens/edit_profile_screen.dart';
import 'package:mushukistan_frontend/features/profile/presentation/screens/profile_screen.dart';

import '../../support/fakes.dart';

Map<String, Object?> _profile() => {
      'id': 'user-one',
      'email': 'synthetic@example.com',
      'name': 'Synthetic Owner',
      'phone_number': '+998 90 123 4567',
      'telegram_username': 'synthetic_cats',
      'bio': 'Synthetic bio',
      'registered_at': '2026-01-01T00:00:00Z',
      'observation_count': 0,
      'total_likes_received': 0,
      'comment_count': 0,
    };

Future<GoRouter> _mount(
  WidgetTester tester, {
  required double scale,
  double width = 390,
  AppLanguage language = AppLanguage.english,
  double keyboard = 0,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);
  final container = ProviderContainer(overrides: [
    mushukistanApiProvider
        .overrideWithValue(MushukistanApi(client: FakeApiClient())),
    profileMeProvider
        .overrideWith((ref) async => UserProfileData.fromJson(_profile())),
    appLanguageProvider.overrideWith((ref) => language),
  ]);
  addTearDown(container.dispose);
  final router = GoRouter(initialLocation: '/profile/edit', routes: [
    GoRoute(
      path: '/profile',
      builder: (_, __) => const Scaffold(body: Text('Profile home')),
      routes: [
        GoRoute(path: 'edit', builder: (_, __) => const EditProfileScreen()),
      ],
    ),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return router;
}

/// The rendered paragraph of [text]: fully laid out, not truncated.
void _expectComplete(WidgetTester tester, String text) {
  final finder = find.text(text);
  expect(finder, findsOneWidget, reason: text);
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  expect(paragraph.didExceedMaxLines, isFalse, reason: text);
  // didExceedMaxLines is what produces the "…" seen in AUTH-209.
  expect(
      paragraph.size.width, lessThanOrEqualTo(tester.view.physicalSize.width));
}

Future<void> _showPhone(WidgetTester tester, String helper) async {
  await tester.scrollUntilVisible(find.text(helper), 200,
      scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}

void main() {
  final english = AppStrings.forLanguage(AppLanguage.english);

  for (final scale in [1.0, 1.3, 2.0]) {
    for (final width in [320.0, 390.0]) {
      testWidgets('phone guidance complete at ${scale}x, ${width.toInt()} dp',
          (tester) async {
        await _mount(tester, scale: scale, width: width);
        await _showPhone(tester, english.uzbekPhoneFormatHelp);
        _expectComplete(tester, english.uzbekPhoneFormatHelp);
        expect(find.text('16/32'), findsOneWidget, reason: 'counter kept');
        expect(tester.takeException(), isNull, reason: 'no overflow');
      });
    }
  }

  for (final language in [AppLanguage.russian, AppLanguage.uzbek]) {
    testWidgets('${language.label}: guidance complete at 2.0x on 320 dp',
        (tester) async {
      final strings = AppStrings.forLanguage(language);
      await _mount(tester, scale: 2, width: 320, language: language);
      await _showPhone(tester, strings.uzbekPhoneFormatHelp);
      _expectComplete(tester, strings.uzbekPhoneFormatHelp);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('validation error is complete at 2.0x and blocks Save',
      (tester) async {
    await _mount(tester, scale: 2, width: 320);
    await _showPhone(tester, english.uzbekPhoneFormatHelp);
    await tester.enterText(
        find.ancestor(
            of: find.text('Phone number'),
            matching: find.byType(TextFormField)),
        '12345');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Save changes'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text(english.invalidUzbekPhone), -200,
        scrollable: find.byType(Scrollable).first);
    _expectComplete(tester, english.invalidUzbekPhone);
    expect(find.text('Could not save changes.'), findsNothing,
        reason: 'no request');
    expect(tester.takeException(), isNull);
  });

  testWidgets('with the keyboard open, guidance and Save/Cancel stay usable',
      (tester) async {
    final router = await _mount(tester, scale: 2, width: 320, keyboard: 300);
    await _showPhone(tester, english.uzbekPhoneFormatHelp);
    _expectComplete(tester, english.uzbekPhoneFormatHelp);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('Cancel'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Save changes'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(router.routerDelegate.currentConfiguration.uri.path, '/profile');
  });
}
