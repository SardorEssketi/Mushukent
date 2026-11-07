// Batch 4 Feed regressions: EMU-101 (category results after failed loads),
// EMU-102 (selected filter visible after returning), EMU-104 (action names),
// EMU-106 (filter touch targets) and AUTH-207 (end of list).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mushukistan_frontend/core/localization/language_controller.dart';
import 'package:mushukistan_frontend/core/network/api_error.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';
import 'package:mushukistan_frontend/features/auth/application/auth_controller.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_models.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_repository.dart';
import 'package:mushukistan_frontend/features/feed/application/feed_intro.dart';
import 'package:mushukistan_frontend/features/feed/presentation/screens/feed_screen.dart';

import '../../support/fakes.dart';

Map<String, Object?> _page(List<Object?> items, [String? cursor]) => {
      'items': items,
      'next_cursor': cursor,
      'limit': 30,
    };

Map<String, Object?> _post(String id,
        {String kind = 'observation', int likes = 3, int comments = 12}) =>
    {
      'item_type': 'observation',
      'id': id,
      'kind': kind,
      'cat': {'id': 'cat-$id', 'name': 'Cat $id', 'status': 'healthy'},
      'author': {'id': 'author-1', 'name': 'Amina'},
      'photo_url': 'invalid:',
      'photo_urls': ['invalid:'],
      'created_at': '2026-09-01T10:00:00Z',
      'like_count': likes,
      'comment_count': comments,
      'is_liked_by_me': false,
    };

Map<String, Object?> _lost(String id) => {
      'item_type': 'lost_pet',
      'id': id,
      'pet_name': 'Lost $id',
      'photo_url': 'invalid:',
      'photo_urls': ['invalid:'],
      'last_seen_location': {'latitude': 41.3, 'longitude': 69.2},
      'is_resolved': false,
      'comment_count': 0,
      'created_at': '2026-09-01T10:00:00Z',
    };

class _DismissedIntro implements FeedIntroStorage {
  @override
  Future<bool> isDismissed() async => true;

  @override
  Future<void> dismiss() async {}
}

const _offline = MushukistanApiException(
  kind: ApiFailureKind.network,
  code: 'NETWORK_ERROR',
  message: 'No connection.',
);

/// A fake backend whose categories can be taken offline one by one.
class _Backend {
  _Backend() {
    client.setHandler('GET', 'feed', (call) {
      final filter = call.queryParameters?['filter'] as String? ?? 'recent';
      if (offline) throw _offline;
      return feed[filter] ?? _page([]);
    });
    client.setHandler('GET', 'lost-pets', (_) {
      if (offline) throw _offline;
      return lost;
    });
    client.setHandler('GET', 'adoption-posts', (_) {
      if (offline) throw _offline;
      return _page([]);
    });
  }

  final client = FakeApiClient();
  bool offline = false;
  Map<String, Map<String, Object?>> feed = {
    'recent': _page([_post('recent-1'), _post('recent-2')]),
    'needs_help': _page([_post('help-1', kind: 'needs_help')]),
    'popular': _page([_post('popular-1')]),
  };
  Map<String, Object?> lost = _page([_lost('lost-1')]);
}

Future<(ProviderContainer, GoRouter)> _mount(
  WidgetTester tester,
  FakeApiClient client, {
  double width = 390,
  double height = 1400,
  AppLanguage language = AppLanguage.english,
  bool signedIn = false,
  double textScale = 1,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(overrides: [
    mushukistanApiProvider.overrideWithValue(MushukistanApi(client: client)),
    authRepositoryProvider.overrideWithValue(signedIn
        ? FakeAuthRepository(
            restoreResult: SessionRestoreSuccess(
                AuthSession.restored(accessToken: 'token', user: testUser())))
        : FakeAuthRepository()),
    googleIdentityTokenProvider
        .overrideWithValue(FakeGoogleIdentityTokenProvider()),
    appLanguageProvider.overrideWith((ref) => language),
    // Keep the welcome card out of the measurements.
    feedIntroStorageProvider.overrideWithValue(_DismissedIntro()),
  ]);
  addTearDown(container.dispose);
  final router = GoRouter(initialLocation: '/feed', routes: [
    GoRoute(path: '/feed', builder: (_, __) => const FeedScreen()),
    GoRoute(
      path: '/auth-required',
      builder: (context, _) => Scaffold(
        body: TextButton(
          onPressed: () => context.go('/feed'),
          child: const Text('Continue browsing'),
        ),
      ),
    ),
    GoRoute(
      path: '/posts/:id',
      builder: (_, state) =>
          Scaffold(body: Text('Post ${state.pathParameters['id']}')),
    ),
    GoRoute(
      path: '/lost-pets/:id',
      builder: (_, state) =>
          Scaffold(body: Text('Lost ${state.pathParameters['id']}')),
    ),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return (container, router);
}

Finder _chip(String label) => find.text(label);

Future<void> _select(WidgetTester tester, String label) async {
  await tester.ensureVisible(_chip(label));
  await tester.pumpAndSettle();
  await tester.tap(_chip(label));
  await tester.pumpAndSettle();
}

/// The horizontal filter strip's scroll position.
ScrollPosition _strip(WidgetTester tester) => tester
    .state<ScrollableState>(find
        .ancestor(of: _chip('Recent'), matching: find.byType(Scrollable))
        .first)
    .position;

/// The tappable region of one filter tab (the area that selects it).
Rect _tabTarget(WidgetTester tester, String value) =>
    tester.getRect(find.byKey(ValueKey('feed-filter-target-$value')));

Rect _pill(WidgetTester tester, String label) => tester.getRect(find
    .ancestor(of: _chip(label), matching: find.byType(AnimatedContainer))
    .first);

void main() {
  group('EMU-101 category results after a failed load', () {
    testWidgets('Recent -> Lost and -> Needs Help offline never show Recent',
        (tester) async {
      final backend = _Backend();
      final (container, _) = await _mount(tester, backend.client);
      expect(find.text('Cat recent-1'), findsOneWidget);

      backend.offline = true;
      await _select(tester, 'Lost pets');
      expect(container.read(feedModeProvider), 'lost_pets');
      expect(find.text('Cat recent-1'), findsNothing);
      expect(find.text('Cat recent-2'), findsNothing);
      // A lasting error with Retry, not a passing snackbar.
      expect(find.text('Could not load this section'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);

      await _select(tester, 'Cat needs help');
      expect(container.read(feedModeProvider), 'needs_help');
      expect(find.text('Cat recent-1'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);
    });

    testWidgets('rapid changes while offline settle on the last filter',
        (tester) async {
      final backend = _Backend();
      final (container, _) = await _mount(tester, backend.client);
      backend.offline = true;
      for (final label in [
        'Popular',
        'Cat needs help',
        'Lost pets',
        'Adoption'
      ]) {
        await tester.ensureVisible(_chip(label));
        await tester.tap(_chip(label));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(container.read(feedModeProvider), 'adoption');
      for (final text in [
        'Cat recent-1',
        'Cat popular-1',
        'Cat help-1',
        'Lost lost-1'
      ]) {
        expect(find.text(text), findsNothing, reason: text);
      }
      expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);
    });

    testWidgets('reconnect + Retry shows the selected category only, once',
        (tester) async {
      final backend = _Backend();
      await _mount(tester, backend.client);
      backend.offline = true;
      await _select(tester, 'Cat needs help');
      backend.offline = false;
      await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Cat help-1'), findsOneWidget);
      expect(find.text('Cat recent-1'), findsNothing);

      // Online -> offline -> online across categories.
      await _select(tester, 'Lost pets');
      expect(find.text('Lost lost-1'), findsOneWidget);
      expect(find.text('Cat help-1'), findsNothing);
      await _select(tester, 'Recent');
      expect(find.text('Cat recent-1'), findsOneWidget);
      expect(find.text('Cat recent-2'), findsOneWidget);
      expect(find.text('Lost lost-1'), findsNothing);
    });

    testWidgets('a failed refresh of the same category keeps its posts',
        (tester) async {
      final backend = _Backend();
      final (container, _) = await _mount(tester, backend.client);
      backend.offline = true;
      await tester.fling(find.text('Cat recent-1'), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      expect(container.read(feedModeProvider), 'recent');
      expect(find.text('Cat recent-1'), findsOneWidget);
      expect(find.text('Cat recent-2'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Retry'), findsNothing);
    });
  });

  group('EMU-102 selected filter stays visible', () {
    for (final width in [320.0, 390.0]) {
      testWidgets('Adoption -> sign-in gate -> Continue browsing at $width dp',
          (tester) async {
        final backend = _Backend();
        final (container, router) =
            await _mount(tester, backend.client, width: width);
        await _select(tester, 'Adoption');
        expect(find.text('No rehoming posts yet.'), findsOneWidget);
        for (var visit = 0; visit < 2; visit++) {
          router.go('/auth-required');
          await tester.pumpAndSettle();
          await tester.tap(find.text('Continue browsing'));
          await tester.pumpAndSettle();
          expect(container.read(feedModeProvider), 'adoption');
          expect(find.text('No rehoming posts yet.'), findsOneWidget);
          final chip = _pill(tester, 'Adoption');
          expect(chip.left, greaterThanOrEqualTo(0), reason: 'visit $visit');
          expect(chip.right, lessThanOrEqualTo(width), reason: 'visit $visit');
        }
      });
    }

    testWidgets('every category is visible after the Feed is rebuilt',
        (tester) async {
      final backend = _Backend();
      final (container, router) =
          await _mount(tester, backend.client, width: 320);
      for (final (mode, label) in [
        ('recent', 'Recent'),
        ('popular', 'Popular'),
        ('needs_help', 'Cat needs help'),
        ('lost_pets', 'Lost pets'),
        ('adoption', 'Adoption'),
      ]) {
        container.read(feedModeProvider.notifier).state = mode;
        router.go('/posts/x');
        await tester.pumpAndSettle();
        router.go('/feed');
        await tester.pumpAndSettle();
        final chip = _pill(tester, label);
        expect(chip.left, greaterThanOrEqualTo(0), reason: label);
        expect(chip.right, lessThanOrEqualTo(320), reason: label);
      }
    });

    testWidgets('tapping a visible chip does not move the strip',
        (tester) async {
      final backend = _Backend();
      await _mount(tester, backend.client, width: 320);
      _strip(tester).jumpTo(40);
      await tester.pump();
      await tester.tap(_chip('Popular'));
      await tester.pumpAndSettle();
      expect(_strip(tester).pixels, 40);
    });

    testWidgets('a partly hidden chip is brought fully into view on selection',
        (tester) async {
      final backend = _Backend();
      await _mount(tester, backend.client, width: 320);
      // The chip that straddles the right edge.
      final label = [
        'Popular',
        'Cat needs help',
        'Lost pets',
        'Adoption',
      ].firstWhere((label) {
        final pill = _pill(tester, label);
        return pill.left < 320 - 16 && pill.right > 320;
      });
      final before = _pill(tester, label);
      await tester.tapAt(Offset(before.left + 8, before.center.dy));
      await tester.pumpAndSettle();
      expect(_pill(tester, label).right, lessThanOrEqualTo(320));
      expect(_pill(tester, label).left, greaterThanOrEqualTo(0));
    });

    testWidgets('resume keeps the selection and strip position',
        (tester) async {
      final backend = _Backend();
      final (container, _) = await _mount(tester, backend.client, width: 320);
      await _select(tester, 'Adoption');
      final offset = _strip(tester).pixels;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(container.read(feedModeProvider), 'adoption');
      expect(_strip(tester).pixels, offset);
    });
  });

  group('EMU-106 filter touch targets', () {
    testWidgets('each tab is at least 48 dp tall; edge taps select it',
        (tester) async {
      final backend = _Backend();
      final (container, _) = await _mount(tester, backend.client);
      for (final (value, label) in [
        ('recent', 'Recent'),
        ('popular', 'Popular'),
        ('needs_help', 'Cat needs help'),
      ]) {
        final target = _tabTarget(tester, value);
        expect(target.height, greaterThanOrEqualTo(48), reason: label);
        expect(_pill(tester, label).height, lessThan(48),
            reason: 'the pill stays compact');
      }
      // Below and above the pill, inside the 48 dp target (the audit tapped
      // ~5 dp below a 36 dp pill of Recent's pill and nothing happened).
      await tester.tap(_chip('Popular'));
      await tester.pumpAndSettle();
      final recent = _pill(tester, 'Recent');
      final recentTarget = _tabTarget(tester, 'recent');
      expect(recentTarget.top, lessThan(recent.top));
      expect(recentTarget.bottom, greaterThan(recent.bottom));
      await tester.tapAt(Offset(recent.center.dx, recent.bottom + 4));
      await tester.pumpAndSettle();
      expect(container.read(feedModeProvider), 'recent');
      final help = _pill(tester, 'Cat needs help');
      await tester.tapAt(Offset(help.center.dx, help.top - 4));
      await tester.pumpAndSettle();
      expect(container.read(feedModeProvider), 'needs_help');
      // Center tap.
      await tester.tap(_chip('Popular'));
      await tester.pumpAndSettle();
      expect(container.read(feedModeProvider), 'popular');
    });

    testWidgets('neighboring targets do not overlap', (tester) async {
      final backend = _Backend();
      final (container, _) = await _mount(tester, backend.client);
      final recent = _tabTarget(tester, 'recent');
      final popular = _tabTarget(tester, 'popular');
      expect(recent.right, lessThanOrEqualTo(popular.left));
      // The gap between them selects neither.
      await tester
          .tapAt(Offset((recent.right + popular.left) / 2, recent.center.dy));
      await tester.pumpAndSettle();
      expect(container.read(feedModeProvider), 'recent');
    });

    testWidgets('large text: targets stay >= 48 dp without overflow',
        (tester) async {
      final backend = _Backend();
      final (container, _) = await _mount(tester, backend.client,
          width: 320, textScale: 2, language: AppLanguage.russian);
      expect(tester.takeException(), isNull);
      final target = _tabTarget(tester, 'recent');
      expect(target.height, greaterThanOrEqualTo(48));
      expect(_pill(tester, 'Новые').height, lessThanOrEqualTo(target.height));
      // Still scrolls horizontally to the last category and selects it.
      await tester.ensureVisible(_chip('Пристройство'));
      await tester.pumpAndSettle();
      await tester.tap(_chip('Пристройство'));
      await tester.pumpAndSettle();
      expect(container.read(feedModeProvider), 'adoption');
      expect(tester.takeException(), isNull);
    });
  });

  group('EMU-104 Feed action names', () {
    SemanticsData action(WidgetTester tester, String label) => tester
        .getSemantics(find.bySemanticsLabel(label).first)
        .getSemanticsData();

    testWidgets('like and comment actions are named with counts and state',
        (tester) async {
      final handle = tester.ensureSemantics();
      final backend = _Backend()
        ..feed['recent'] = _page([
          _post('zero', likes: 0, comments: 0),
          _post('one', likes: 1, comments: 1),
          _post('many', likes: 4, comments: 12),
        ]);
      await _mount(tester, backend.client, signedIn: true);
      for (final label in [
        'Like, 0',
        'Comments, 0',
        'Like, 1',
        'Comments, 1',
        'Like, 4',
        'Comments, 12',
      ]) {
        final data = action(tester, label);
        expect(data.hasAction(SemanticsAction.tap), isTrue, reason: label);
        expect(data.hasFlag(SemanticsFlag.isButton), isTrue, reason: label);
      }
      final like = action(tester, 'Like, 4');
      expect(like.hasFlag(SemanticsFlag.hasToggledState), isTrue);
      expect(like.hasFlag(SemanticsFlag.isToggled), isFalse);
      // No bare-number nodes left.
      expect(find.bySemanticsLabel(RegExp(r'^\d+$')), findsNothing);
      handle.dispose();
    });

    testWidgets('liking updates the name, count and state; failure rolls back',
        (tester) async {
      final handle = tester.ensureSemantics();
      final backend = _Backend()
        ..feed['recent'] = _page([_post('one', likes: 4, comments: 1)]);
      var fail = false;
      backend.client.setHandler('POST', 'posts/one/likes', (_) {
        if (fail) throw _offline;
        return {'liked': true, 'like_count': 5};
      });
      backend.client.setHandler('DELETE', 'posts/one/likes', (_) {
        if (fail) throw _offline;
        return {'liked': false, 'like_count': 4};
      });
      await _mount(tester, backend.client, signedIn: true);
      await tester.tap(find.bySemanticsLabel('Like, 4'));
      await tester.pumpAndSettle();
      final unlike = action(tester, 'Unlike, 5');
      expect(unlike.hasFlag(SemanticsFlag.isToggled), isTrue);

      fail = true;
      await tester.tap(find.bySemanticsLabel('Unlike, 5'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Unlike, 5'), findsOneWidget,
          reason: 'optimistic change rolled back');
      handle.dispose();
    });

    testWidgets('guest like asks to sign in; comments open the post',
        (tester) async {
      final handle = tester.ensureSemantics();
      final backend = _Backend()
        ..feed['recent'] = _page([_post('one', likes: 2, comments: 3)]);
      final (_, router) = await _mount(tester, backend.client);
      await tester.tap(find.bySemanticsLabel('Like, 2'));
      await tester.pumpAndSettle();
      expect(find.text('Continue browsing'), findsOneWidget);
      expect(backend.client.calls.where((c) => c.method == 'POST'), isEmpty);

      await tester.tap(find.text('Continue browsing'));
      await tester.pumpAndSettle();
      // Keyboard: focus the Comments action and press Enter.
      final comments = find.byTooltip('Comments').first;
      Focus.of(tester.element(find.descendant(
              of: comments, matching: find.byIcon(Icons.chat_bubble_outline))))
          .requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Post one'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('names are localized in Russian and Uzbek', (tester) async {
      final handle = tester.ensureSemantics();
      final backend = _Backend()
        ..feed['recent'] = _page([_post('one', likes: 2, comments: 3)]);
      await _mount(tester, backend.client, language: AppLanguage.russian);
      expect(find.bySemanticsLabel(RegExp(r'^Лайк, 2$')), findsOneWidget);
      expect(
          find.bySemanticsLabel(RegExp(r'^Комментарии, 3$')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await _mount(tester, backend.client, language: AppLanguage.uzbek);
      expect(find.bySemanticsLabel(RegExp(r'^Layk, 2$')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Izohlar, 3$')), findsOneWidget);
      handle.dispose();
    });
  });

  group('AUTH-207 end of list', () {
    Finder end() => find.text('No more posts.');

    testWidgets('empty Feed shows its empty state, not the end marker',
        (tester) async {
      final backend = _Backend()..feed['recent'] = _page([]);
      await _mount(tester, backend.client);
      expect(end(), findsNothing);
    });

    testWidgets('one page without a cursor ends with the marker',
        (tester) async {
      final backend = _Backend();
      await _mount(tester, backend.client);
      await tester.scrollUntilVisible(end(), 300,
          scrollable: find.byType(Scrollable).first);
      expect(end(), findsOneWidget);
    });

    testWidgets('marker only after the last page; never while loading',
        (tester) async {
      final backend = _Backend();
      final second = Completer<Map<String, Object?>>();
      var pageFails = true;
      backend.client.setHandler('GET', 'feed', (call) {
        final cursor = call.queryParameters?['cursor'];
        if (cursor == null) {
          return _page([for (var i = 0; i < 30; i++) _post('p$i')], 'c2');
        }
        if (cursor == 'c2') {
          if (pageFails) {
            pageFails = false;
            throw _offline;
          }
          return second.future;
        }
        return _page([]);
      });
      await _mount(tester, backend.client, height: 900);
      expect(end(), findsNothing, reason: 'more pages exist');
      // Scroll to the bottom: the second page fails first.
      await tester.dragUntilVisible(find.text('Retry'),
          find.byType(CustomScrollView), const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(end(), findsNothing, reason: 'page error is not the end');
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(end(), findsNothing, reason: 'still loading');
      second.complete(_page([_post('last')]));
      await tester.pumpAndSettle();
      await tester.dragUntilVisible(
          end(), find.byType(CustomScrollView), const Offset(0, -600));
      expect(end(), findsOneWidget);
      expect(find.text('Cat last'), findsOneWidget);
      // Exactly one request per cursor (no duplicate page loads).
      final cursors = backend.client.calls
          .where((c) => c.path == 'feed')
          .map((c) => c.queryParameters?['cursor'])
          .toList();
      expect(cursors.where((c) => c == 'c2').length, 2,
          reason: 'one failed attempt + one Retry');
    });

    testWidgets('page-size results followed by an empty last page',
        (tester) async {
      final backend = _Backend();
      backend.client.setHandler('GET', 'feed', (call) {
        if (call.queryParameters?['cursor'] == null) {
          return _page([for (var i = 0; i < 30; i++) _post('p$i')], 'c2');
        }
        return _page([]);
      });
      await _mount(tester, backend.client, height: 900);
      await tester.dragUntilVisible(
          end(), find.byType(CustomScrollView), const Offset(0, -800));
      expect(end(), findsOneWidget);
      expect(find.text('Cat p29'), findsOneWidget);
    });

    testWidgets('filter change and refresh reset the marker', (tester) async {
      final backend = _Backend();
      final pending = Completer<Map<String, Object?>>();
      backend.client.setHandler('GET', 'lost-pets', (_) => pending.future);
      await _mount(tester, backend.client);
      expect(end(), findsOneWidget);
      await _select(tester, 'Lost pets');
      expect(end(), findsNothing, reason: 'new category still loading');
      pending.complete(_page([_lost('lost-1')], 'next'));
      backend.client
          .setHandler('GET', 'lost-pets', (_) => _page([_lost('lost-2')]));
      await tester.pumpAndSettle();
      await tester.dragUntilVisible(
          end(), find.byType(CustomScrollView), const Offset(0, -300));
      expect(end(), findsOneWidget);
      expect(find.text('Lost lost-2'), findsOneWidget);
    });

    testWidgets('localized in Russian and Uzbek', (tester) async {
      final backend = _Backend();
      await _mount(tester, backend.client, language: AppLanguage.russian);
      expect(find.text('Больше публикаций нет.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await _mount(tester, backend.client, language: AppLanguage.uzbek);
      expect(find.text('Boshqa postlar yo‘q.'), findsOneWidget);
    });
  });
}
