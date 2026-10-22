import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mushukistan_frontend/core/localization/app_strings.dart';
import 'package:mushukistan_frontend/core/localization/language_controller.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';
import 'package:mushukistan_frontend/core/theme/app_theme.dart';
import 'package:mushukistan_frontend/features/feed/presentation/screens/feed_screen.dart';
import 'package:mushukistan_frontend/features/feed/presentation/widgets/feed_card_parts.dart';

import '../../support/fakes.dart';

Map<String, Object?> _page(List<Object?> items) => {
      'items': items,
      'next_cursor': null,
      'limit': 30,
    };

Map<String, Object?> _post(
  String id, {
  String kind = 'observation',
  Map<String, Object?>? location,
  List<String> photos = const ['invalid:'],
}) =>
    {
      'item_type': 'observation',
      'id': id,
      'kind': kind,
      'cat': {'id': 'cat-$id', 'name': 'Cat $id', 'status': 'unknown'},
      'author': {'id': 'author-1', 'name': 'Amina'},
      'photo_url': photos.first,
      'photo_urls': photos,
      'description': 'Limping near the bus stop.',
      'location': location,
      'created_at': '2026-09-01T10:00:00Z',
      'like_count': 0,
      'comment_count': 0,
      'is_liked_by_me': false,
    };

const _tashkent = {'latitude': 41.3111, 'longitude': 69.2797};

void _size(WidgetTester tester, double width, double height) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<GoRouter> _pumpRouted(
  WidgetTester tester,
  List<Object?> items, {
  AppLanguage language = AppLanguage.english,
  ThemeData? theme,
}) async {
  final client = FakeApiClient()
    ..setHandler('GET', 'feed', (_) => _page(items));
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, __) => const FeedScreen()),
    GoRoute(
      path: '/map',
      builder: (_, state) => Scaffold(body: Text('Map ${state.uri.query}')),
    ),
    GoRoute(
      path: '/register',
      builder: (_, __) => const Scaffold(body: Text('Register screen')),
    ),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      mushukistanApiProvider.overrideWithValue(MushukistanApi(client: client)),
      appLanguageProvider.overrideWith((ref) => language),
    ],
    child: MaterialApp.router(
      theme: theme ?? AppTheme.light,
      routerConfig: router,
    ),
  ));
  await tester.pumpAndSettle();
  return router;
}

Map<String, Object?> _lost(String id, Object? location) => {
      'item_type': 'lost_pet',
      'id': id,
      'pet_name': 'Lost $id',
      'owner_phone_number': '+998901234567',
      'photo_url': 'invalid:',
      'photo_urls': ['invalid:'],
      'last_seen_location': location,
      'additional_info': 'Last seen near the park',
      'is_resolved': false,
      'comment_count': 0,
      'created_at': '2026-09-01T10:00:00Z',
    };

void main() {
  group('Lost Pet View on map', () {
    testWidgets('opens the Map at the pet coordinates with the pet id',
        (tester) async {
      _size(tester, 390, 1400);
      await _pumpRouted(tester, [_lost('milo', _tashkent)]);
      final action = find.byKey(const ValueKey('lost-pet-view-on-map'));
      expect(action, findsOneWidget);
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(find.text('Map lat=41.3111&lon=69.2797&lostPetId=milo'),
          findsOneWidget);
    });

    testWidgets('shows for a point exactly on the Map boundary',
        (tester) async {
      _size(tester, 390, 1400);
      await _pumpRouted(tester, [
        _lost('edge', {'latitude': 41.18, 'longitude': 69.05}),
      ]);
      expect(
          find.byKey(const ValueKey('lost-pet-view-on-map')), findsOneWidget);
    });

    testWidgets('is hidden for missing, malformed or outside locations',
        (tester) async {
      _size(tester, 390, 4000);
      await _pumpRouted(tester, [
        _lost('missing', null),
        _lost('malformed', {'latitude': 'abc', 'longitude': 'x'}),
        _lost('samarkand', {'latitude': 39.65, 'longitude': 66.96}),
        _lost('just-outside', {'latitude': 41.1799, 'longitude': 69.2}),
      ]);
      expect(find.text('Lost Pet'), findsWidgets);
      expect(find.byKey(const ValueKey('lost-pet-view-on-map')), findsNothing);
      expect(find.text('View on map'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('Cat needs help View on map', () {
    testWidgets('opens the Map at the post coordinates with needs-help focus',
        (tester) async {
      _size(tester, 390, 1400);
      await _pumpRouted(
          tester, [_post('help', kind: 'needs_help', location: _tashkent)]);

      final action = find.byKey(const ValueKey('needs-help-view-on-map'));
      expect(action, findsOneWidget);
      expect(find.descendant(of: action, matching: find.text('View on map')),
          findsOneWidget);
      // Likes and comments stay alongside the new action.
      expect(find.byIcon(Icons.favorite_outline), findsOneWidget);
      expect(find.byTooltip('Comments'), findsOneWidget);

      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(find.text('Map lat=41.3111&lon=69.2797&focus=needs_help'),
          findsOneWidget);
    });

    testWidgets('is hidden without a location or outside the Map area',
        (tester) async {
      _size(tester, 390, 3000);
      await _pumpRouted(tester, [
        _post('none', kind: 'needs_help'),
        _post('null-island',
            kind: 'needs_help', location: {'latitude': 0, 'longitude': 0}),
        _post('samarkand',
            kind: 'needs_help',
            location: {'latitude': 39.65, 'longitude': 66.96}),
      ]);
      expect(find.text('Cat needs help'), findsWidgets);
      expect(
          find.byKey(const ValueKey('needs-help-view-on-map')), findsNothing);
      expect(find.text('View on map'), findsNothing);
    });

    testWidgets('ordinary posts keep likes and comments only', (tester) async {
      _size(tester, 390, 1400);
      await _pumpRouted(tester, [_post('plain', location: _tashkent)]);
      expect(find.byType(FeedPostCard), findsOneWidget);
      expect(find.text('View on map'), findsNothing);
    });

    testWidgets('fits narrow screens in every language and theme',
        (tester) async {
      for (final (width, language, dark) in [
        (320.0, AppLanguage.russian, false),
        (320.0, AppLanguage.uzbek, true),
        (360.0, AppLanguage.english, true),
        (430.0, AppLanguage.russian, false),
      ]) {
        _size(tester, width, 1400);
        await _pumpRouted(
          tester,
          [_post('help', kind: 'needs_help', location: _tashkent)],
          language: language,
          theme: dark ? AppTheme.dark : AppTheme.light,
        );
        expect(tester.takeException(), isNull,
            reason: '$width ${language.code}');
        final action = find.byKey(const ValueKey('needs-help-view-on-map'));
        expect(action, findsOneWidget);
        final card = tester.getRect(find.byType(FeedCardFrame));
        expect(tester.getRect(action).right, lessThanOrEqualTo(card.right));
      }
    });
  });

  group('compact guest welcome card', () {
    testWidgets('is short on phones and keeps both actions', (tester) async {
      _size(tester, 390, 1400);
      await _pumpRouted(tester, [_post('one')]);

      final headline = find.text('Helping cats and pets across Uzbekistan');
      final card = find
          .ancestor(of: headline, matching: find.byType(DecoratedBox))
          .first;
      // flutter_test renders text in a wide square-glyph font, so copy wraps
      // more than with Manrope; the previous card measured ~204px here.
      expect(tester.getSize(card).height, lessThan(185));
      // The first post starts well within the first phone screen.
      expect(tester.getTopLeft(find.byType(FeedCardFrame)).dy, lessThan(300));

      await tester.tap(find.text('Create account'));
      await tester.pumpAndSettle();
      expect(find.text('Register screen'), findsOneWidget);
    });

    testWidgets('Map action opens the Map', (tester) async {
      _size(tester, 390, 1400);
      await _pumpRouted(tester, [_post('one')]);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Map'));
      await tester.pumpAndSettle();
      expect(find.text('Map '), findsOneWidget);
    });

    testWidgets('wraps without overflow at 320px in all languages',
        (tester) async {
      for (final language in AppLanguage.values) {
        for (final dark in [false, true]) {
          _size(tester, 320, 1400);
          await _pumpRouted(tester, [_post('one')],
              language: language, theme: dark ? AppTheme.dark : AppTheme.light);
          expect(tester.takeException(), isNull, reason: language.code);
          expect(find.byType(FilledButton), findsOneWidget);
          expect(find.byType(OutlinedButton), findsOneWidget);
        }
      }
    });
  });

  group('Feed media frame', () {
    test('backdrop renders once into a small bitmap at device resolution',
        () async {
      // A half-red, half-blue portrait source.
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(const Rect.fromLTWH(0, 0, 30, 80),
          Paint()..color = const Color(0xFFFF0000));
      canvas.drawRect(const Rect.fromLTWH(30, 0, 30, 80),
          Paint()..color = const Color(0xFF0000FF));
      final source = await recorder.endRecording().toImage(60, 80);

      for (final (frame, ratio) in [
        (const Size(366, 329), 2.625),
        (const Size(728, 420), 1.0),
      ]) {
        final image = await renderFeedBackdrop(source, frame, ratio);
        expect(
            image.width, (frame.width / feedBackdropDownscale * ratio).ceil());
        expect(image.height,
            (frame.height / feedBackdropDownscale * ratio).ceil());
        // The blur blends the two halves at the seam instead of a hard edge.
        final bytes = (await image.toByteData())!;
        final mid = image.height ~/ 2;
        final seam = (mid * image.width + image.width ~/ 2) * 4;
        expect(bytes.getUint8(seam), inExclusiveRange(10, 245)); // red
        expect(bytes.getUint8(seam + 2), inExclusiveRange(10, 245)); // blue
        image.dispose();
      }
      source.dispose();
    });

    Future<void> pumpMedia(WidgetTester tester, double width,
        {List<String> photos = const ['invalid:a', 'invalid:b']}) async {
      _size(tester, width, 1200);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width - 24,
              child: FeedMedia(
                photoUrl: photos.first,
                photoUrls: photos,
                strings: AppStrings.forLanguage(AppLanguage.english),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('frame is fixed, contained, and responsive', (tester) async {
      for (final width in [320.0, 360.0, 390.0, 430.0, 800.0, 1280.0]) {
        await pumpMedia(tester, width);
        final frame = tester.getSize(find.byKey(const ValueKey('feed-media')));
        final cardWidth = width - 24;
        final expected = width < 700
            ? (cardWidth * 0.9).clamp(0, 380)
            : (cardWidth * 0.6).clamp(0, 420);
        expect(frame.height, moreOrLessEquals(expected.toDouble()),
            reason: '$width');
        // Photos are never cropped.
        final image = tester.widget<Image>(find.byType(Image).first);
        expect(image.fit, BoxFit.contain);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('failed photos show the fallback and no backdrop',
        (tester) async {
      await pumpMedia(tester, 390, photos: const ['invalid:only']);
      expect(find.byIcon(Icons.image_not_supported_outlined), findsOneWidget);
      expect(find.byType(RawImage), findsNothing);
      expect(find.byType(ImageFiltered), findsNothing);
    });

    testWidgets('gallery controls are compact with 48px hit areas',
        (tester) async {
      await pumpMedia(tester, 390);
      final next = find.byTooltip('Next photo');
      expect(next, findsOneWidget);
      expect(find.text('1/2'), findsOneWidget);
      final hit = tester.getSize(
          find.ancestor(of: next, matching: find.byType(IconButton)).first);
      expect(hit.width, greaterThanOrEqualTo(48));
      expect(hit.height, greaterThanOrEqualTo(48));
      final disc = tester.getSize(find
          .descendant(
              of: find.byType(IconButton), matching: find.byType(Material))
          .first);
      expect(disc.width, lessThanOrEqualTo(36));

      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(find.text('2/2'), findsOneWidget);
      expect(find.byTooltip('Previous photo'), findsOneWidget);
    });
  });
}
