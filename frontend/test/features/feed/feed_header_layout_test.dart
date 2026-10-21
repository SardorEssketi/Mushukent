import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/core/localization/language_controller.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';
import 'package:mushukistan_frontend/core/theme/app_theme.dart';
import 'package:mushukistan_frontend/features/auth/application/auth_controller.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_models.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_repository.dart';
import 'package:mushukistan_frontend/features/feed/presentation/screens/feed_screen.dart';
import 'package:mushukistan_frontend/features/feed/presentation/widgets/feed_card_parts.dart';
import 'package:mushukistan_frontend/features/notifications/presentation/notification_center_screen.dart';

import '../../support/fakes.dart';

Map<String, Object?> _page(List<Object?> items) => {
      'items': items,
      'next_cursor': null,
      'limit': 30,
    };

Map<String, Object?> _observation(String id, {String? authorName}) => {
      'item_type': 'observation',
      'id': id,
      'kind': 'observation',
      'cat': {'id': 'cat-$id', 'name': 'Cat $id', 'status': 'healthy'},
      'author': {'id': 'author-1', 'name': authorName ?? 'Amina'},
      'photo_url': 'invalid:',
      'photo_urls': ['invalid:', 'invalid:second'],
      'description': 'A calm cat near the bakery. ' * 6,
      'created_at': '2026-09-01T10:00:00Z',
      'like_count': 3,
      'comment_count': 1,
      'is_liked_by_me': false,
    };

Map<String, Object?> _lost(String id) => {
      'item_type': 'lost_pet',
      'id': id,
      'pet_name': 'Lost Milo',
      'owner_phone_number': '+998901234567',
      'photo_url': 'invalid:',
      'photo_urls': ['invalid:'],
      'last_seen_location': {'latitude': 41.3, 'longitude': 69.2},
      'additional_info': 'Last seen near the park',
      'is_resolved': false,
      'comment_count': 5,
      'created_at': '2026-09-01T10:00:00Z',
    };

void _size(WidgetTester tester, double width, double height) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

FakeApiClient _client(List<Object?> items) =>
    FakeApiClient()..setHandler('GET', 'feed', (_) => _page(items));

Future<void> _pump(
  WidgetTester tester,
  FakeApiClient client, {
  bool authenticated = false,
  AppLanguage language = AppLanguage.english,
  ThemeData? theme,
  double textScale = 1,
  Key? key,
}) async {
  await tester.pumpWidget(ProviderScope(
    key: key,
    overrides: [
      mushukistanApiProvider.overrideWithValue(MushukistanApi(client: client)),
      appLanguageProvider.overrideWith((ref) => language),
      if (authenticated) ...[
        authRepositoryProvider.overrideWithValue(FakeAuthRepository(
          restoreResult: SessionRestoreSuccess(AuthSession.restored(
            accessToken: 'test-token',
            user: testUser(),
          )),
        )),
        googleIdentityTokenProvider.overrideWithValue(
          FakeGoogleIdentityTokenProvider(),
        ),
      ],
    ],
    child: MaterialApp(
      theme: theme ?? AppTheme.light,
      home: MediaQuery.withClampedTextScaling(
        minScaleFactor: textScale,
        maxScaleFactor: textScale,
        child: const FeedScreen(),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('phone header shows the wordmark, guest login, then filters',
      (tester) async {
    _size(tester, 390, 1400);
    await _pump(tester, _client([_observation('one')]));

    final title = find.text('Mushukistan');
    expect(title, findsOneWidget);
    expect(find.text('Login'), findsOneWidget);
    expect(find.byType(NotificationBell), findsNothing);
    // Title sits inside the compact toolbar, not in a tall empty band.
    expect(tester.getSize(find.byType(AppBar)).height, kToolbarHeight);
    expect(
      find.ancestor(of: title, matching: find.byType(AppBar)),
      findsOneWidget,
    );
    // Filters come directly under the header, before the guest welcome card.
    final recentY = tester.getTopLeft(find.text('Recent')).dy;
    final welcomeY = tester
        .getTopLeft(find.text('Helping cats and pets across Uzbekistan'))
        .dy;
    expect(recentY, lessThan(welcomeY));
    expect(
        recentY - tester.getBottomLeft(find.byType(AppBar)).dy, lessThan(24));
  });

  testWidgets('signed-in header shows the notification bell, not login',
      (tester) async {
    _size(tester, 390, 1000);
    await _pump(tester, _client([_observation('one')]), authenticated: true);

    expect(find.text('Mushukistan'), findsOneWidget);
    expect(find.byType(NotificationBell), findsOneWidget);
    expect(find.text('Login'), findsNothing);
    expect(find.text('Helping cats and pets across Uzbekistan'), findsNothing);
  });

  testWidgets('wide layouts title the section and align it with the cards',
      (tester) async {
    _size(tester, 1280, 1000);
    await _pump(tester, _client([_observation('one')]), authenticated: true);

    // The navigation rail carries the brand on wide screens.
    expect(find.text('Mushukistan'), findsNothing);
    final title =
        find.descendant(of: find.byType(AppBar), matching: find.text('Feed'));
    expect(title, findsOneWidget);
    final cardLeft = tester.getTopLeft(find.byType(FeedCardFrame).first).dx;
    expect(tester.getTopLeft(title).dx, moreOrLessEquals(cardLeft));
    expect(
      tester.getTopLeft(find.text('Recent')).dx,
      greaterThan(cardLeft),
    );
  });

  testWidgets('cards, header and filters fit every width, theme and language',
      (tester) async {
    final client = _client([
      _observation('one',
          authorName: 'Abdurakhmonova Gulnorakhon Shavkatovna-Tashkentskaya'),
      _lost('lost'),
    ]);
    for (final (width, language, dark) in [
      (320.0, AppLanguage.russian, false),
      (360.0, AppLanguage.uzbek, true),
      (390.0, AppLanguage.english, false),
      (430.0, AppLanguage.russian, true),
      (800.0, AppLanguage.uzbek, false),
      (1280.0, AppLanguage.english, true),
    ]) {
      _size(tester, width, 900);
      await _pump(
        tester,
        client,
        language: language,
        theme: dark ? AppTheme.dark : AppTheme.light,
        key: ValueKey('$width-${language.code}-$dark'),
      );
      expect(tester.takeException(), isNull, reason: '$width ${language.code}');
      final card = find.byType(FeedCardFrame).first;
      final cardLeft = tester.getTopLeft(card).dx;
      final gutter = width < 560 ? 12.0 : 16.0;
      if (width < 720) expect(cardLeft, gutter);
      final media =
          tester.getSize(find.byKey(const ValueKey('feed-media')).first);
      // Phones: 0.9 of the card width, at most 380; wider: at most 420.
      expect(media.height, lessThanOrEqualTo(width < 700 ? 380 : 420));
      expect(media.height, lessThan(media.width + 1));
    }
  });

  testWidgets('large text scale at 320px keeps the header and cards intact',
      (tester) async {
    _size(tester, 320, 900);
    await _pump(tester, _client([_observation('one'), _lost('lost')]),
        language: AppLanguage.russian, textScale: 1.3);
    expect(tester.takeException(), isNull);
    expect(find.text('Mushukistan'), findsOneWidget);
    expect(find.text('Войти'), findsOneWidget);
  });
}
