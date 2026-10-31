import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/core/lifecycle/app_resume.dart';
import 'package:mushukistan_frontend/core/network/api_error.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';
import 'package:mushukistan_frontend/core/theme/app_theme.dart';
import 'package:mushukistan_frontend/features/auth/application/auth_controller.dart';
import 'package:mushukistan_frontend/features/feed/presentation/screens/feed_screen.dart';

import '../../support/fakes.dart';

Map<String, Object?> _post(String id) => {
      'item_type': 'observation',
      'id': id,
      'kind': 'observation',
      'cat': {'id': 'cat-$id', 'name': 'Cat $id', 'status': 'healthy'},
      'author': {'id': 'author-1', 'name': 'Amina'},
      'photo_url': 'invalid:',
      'photo_urls': ['invalid:'],
      'description': 'Story $id',
      'created_at': '2026-09-01T10:00:00Z',
      'like_count': 0,
      'comment_count': 0,
      'is_liked_by_me': false,
    };

/// The server side of the feed: what the first page returns can change while the app is away,
/// and it can go offline.
class _FeedServer {
  _FeedServer(this.firstPage, {this.secondPage = const [], this.cursor});

  List<String> firstPage;
  List<String> secondPage;
  String? cursor;
  bool offline = false;
  Completer<void>? gate;

  /// What the "Popular" filter returns (other filters return [firstPage]).
  List<String>? popularPage;

  void install(FakeApiClient client) {
    client.setHandler('GET', 'feed', (call) async {
      final pending = gate;
      if (pending != null) await pending.future;
      if (offline) {
        throw const MushukistanApiException(
          kind: ApiFailureKind.network,
          code: 'NETWORK_ERROR',
          message: 'offline',
        );
      }
      final requested = call.queryParameters?['cursor'];
      final popular = call.queryParameters?['filter'] == 'popular';
      final ids = requested != null
          ? secondPage
          : (popular ? popularPage ?? firstPage : firstPage);
      return {
        'items': [for (final id in ids) _post(id)],
        'next_cursor': requested == null ? cursor : null,
        'limit': 30,
      };
    });
  }
}

class _Harness {
  _Harness(this.container, this.client);

  final ProviderContainer container;
  final FakeApiClient client;
  Duration now = const Duration(hours: 1);

  int get feedRequests =>
      client.calls.where((call) => call.path == 'feed').length;

  /// The app goes to the background for [duration] and comes back (Android's event order).
  void awayFor(Duration duration) {
    final tracker = container.read(appResumeProvider.notifier);
    for (final state in const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tracker.handleLifecycle(state);
    }
    now += duration;
    for (final state in const [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tracker.handleLifecycle(state);
    }
  }
}

List<String> _ids(String prefix, int count) =>
    [for (var i = 0; i < count; i++) '$prefix$i'];

Future<_Harness> _pumpFeed(WidgetTester tester, _FeedServer server) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final client = FakeApiClient();
  server.install(client);
  late _Harness harness;
  final container = ProviderContainer(overrides: [
    mushukistanApiProvider.overrideWithValue(MushukistanApi(client: client)),
    authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
    googleIdentityTokenProvider
        .overrideWithValue(FakeGoogleIdentityTokenProvider()),
    monotonicClockProvider.overrideWithValue(() => harness.now),
  ]);
  addTearDown(container.dispose);
  harness = _Harness(container, client);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(theme: AppTheme.light, home: const FeedScreen()),
  ));
  await tester.pumpAndSettle();
  return harness;
}

Finder _story(String id) => find.text('Story $id');
final _newPosts = find.byKey(const ValueKey('feed-new-posts'));

/// The feed's own vertical list (the filter chips scroll too).
final _feedList = find.descendant(
  of: find.byType(CustomScrollView),
  matching: find.byType(Scrollable),
);

ScrollPosition _scroll(WidgetTester tester) =>
    tester.state<ScrollableState>(_feedList.first).position;

/// Scrolls to the end of what is loaded, which makes the feed fetch its next page.
Future<void> _scrollToEnd(WidgetTester tester) async {
  _scroll(tester).jumpTo(_scroll(tester).maxScrollExtent);
  await tester.pumpAndSettle();
}

int _cursorRequests(_Harness h) =>
    h.client.calls.where((c) => c.queryParameters?['cursor'] == 'c2').length;

Future<void> _scrollDown(WidgetTester tester, double by) async {
  _scroll(tester).jumpTo(_scroll(tester).pixels + by);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('back after 1 minute: no request, nothing changes',
      (tester) async {
    final server = _FeedServer(['a', 'b']);
    final h = await _pumpFeed(tester, server);
    final requests = h.feedRequests;
    server.firstPage = ['new', 'a', 'b'];

    h.awayFor(const Duration(minutes: 1));
    await tester.pumpAndSettle();

    expect(h.feedRequests, requests);
    expect(_story('new'), findsNothing);
  });

  testWidgets('back after 5 minutes at the top: quiet refresh in place',
      (tester) async {
    final server = _FeedServer(['a', 'b']);
    final h = await _pumpFeed(tester, server);
    final requests = h.feedRequests;
    server.firstPage = ['new', 'a', 'b'];
    final gate = server.gate = Completer<void>();

    h.awayFor(const Duration(minutes: 5));
    await tester.pump();
    // While the request runs the posts stay on screen, with no loading screen.
    expect(_story('a'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    gate.complete();
    server.gate = null;
    await tester.pumpAndSettle();
    expect(h.feedRequests, requests + 1);
    expect(_story('new'), findsOneWidget);
    expect(_scroll(tester).pixels, 0);
    expect(_newPosts, findsNothing);
  });

  testWidgets('repeated resume events while a check runs: one request',
      (tester) async {
    final server = _FeedServer(['a', 'b']);
    final h = await _pumpFeed(tester, server);
    final requests = h.feedRequests;
    final gate = server.gate = Completer<void>();

    h.awayFor(const Duration(minutes: 6));
    await tester.pump();
    h.awayFor(const Duration(minutes: 7));
    await tester.pump();
    h.container
        .read(appResumeProvider.notifier)
        .handleLifecycle(AppLifecycleState.resumed);
    await tester.pump();

    gate.complete();
    server.gate = null;
    await tester.pumpAndSettle();
    expect(h.feedRequests, requests + 1);
  });

  group('reading further down', () {
    testWidgets('keeps the position and offers new posts only when there are',
        (tester) async {
      final server = _FeedServer(_ids('p', 30));
      final h = await _pumpFeed(tester, server);
      await _scrollDown(tester, 2500);
      final offset = _scroll(tester).pixels;
      expect(offset, greaterThan(1000));

      // Nothing new on the server: no button, nothing moves.
      h.awayFor(const Duration(minutes: 10));
      await tester.pumpAndSettle();
      expect(_newPosts, findsNothing);
      expect(_scroll(tester).pixels, offset);

      server.firstPage = ['fresh', ..._ids('p', 29)];
      h.awayFor(const Duration(minutes: 10));
      await tester.pumpAndSettle();
      expect(_newPosts, findsOneWidget);
      expect(find.text('New posts'), findsOneWidget);
      expect(_scroll(tester).pixels, offset);
      // The list itself is unchanged until the reader asks.
      _scroll(tester).jumpTo(0);
      await tester.pumpAndSettle();
      expect(_story('fresh'), findsNothing);
    });

    testWidgets(
        'the New posts button reveals them at the top, without duplicates',
        (tester) async {
      // The second page repeats p5 (the server's paging overlaps): it must show only once.
      final server = _FeedServer(
        _ids('p', 30),
        secondPage: ['p5', ..._ids('q', 10)],
        cursor: 'c2',
      );
      final h = await _pumpFeed(tester, server);
      await _scrollToEnd(tester);
      await _scrollToEnd(tester);
      expect(_cursorRequests(h), 1);

      server.firstPage = ['fresh', ..._ids('p', 29)];
      h.awayFor(const Duration(minutes: 10));
      await tester.pumpAndSettle();
      // Checking for new posts does not touch the pages already read.
      expect(_cursorRequests(h), 1);
      await tester.tap(_newPosts);
      await tester.pumpAndSettle();

      expect(_scroll(tester).pixels, 0);
      expect(_newPosts, findsNothing);
      expect(_story('fresh'), findsOneWidget);

      // Paging starts again from the new first page, once, and still shows each post once.
      await _scrollToEnd(tester);
      await _scrollToEnd(tester);
      expect(_cursorRequests(h), 2);
      expect(_story('q9'), findsOneWidget);
      expect(_story('p5'), findsNothing, reason: 'the repeated p5 is skipped');
    });

    testWidgets('changing the filter drops a pending New posts button',
        (tester) async {
      final server = _FeedServer(_ids('p', 30));
      final h = await _pumpFeed(tester, server);
      await _scrollDown(tester, 2500);
      server.firstPage = ['fresh', ..._ids('p', 29)];
      h.awayFor(const Duration(minutes: 10));
      await tester.pumpAndSettle();
      expect(_newPosts, findsOneWidget);

      h.container.read(feedModeProvider.notifier).state = 'popular';
      await tester.pumpAndSettle();
      expect(_newPosts, findsNothing);
    });
  });

  testWidgets('an answer that arrives after the filter changed is ignored',
      (tester) async {
    final server = _FeedServer(_ids('p', 30));
    final h = await _pumpFeed(tester, server);
    await _scrollDown(tester, 2500);

    // A slow check for new posts starts for "Recent"...
    server.firstPage = ['fresh', ..._ids('p', 29)];
    final slow = server.gate = Completer<void>();
    h.awayFor(const Duration(minutes: 10));
    await tester.pump();

    // ...and the reader switches to "Popular" before it answers. That list does not contain
    // "fresh", so only a dropped answer keeps the button away.
    server.gate = null;
    server.popularPage = _ids('pop', 30);
    h.container.read(feedModeProvider.notifier).state = 'popular';
    await tester.pumpAndSettle();
    final popularOffset = _scroll(tester).pixels;

    slow.complete();
    await tester.pumpAndSettle();
    expect(_newPosts, findsNothing);
    expect(_scroll(tester).pixels, popularOffset);
    expect(h.container.read(feedModeProvider), 'popular');
  });

  group('offline', () {
    testWidgets('at the top: the posts stay and nothing is announced',
        (tester) async {
      final server = _FeedServer(['a', 'b']);
      final h = await _pumpFeed(tester, server);
      server.offline = true;

      h.awayFor(const Duration(minutes: 10));
      await tester.pumpAndSettle();
      expect(_story('a'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);

      // Pull-to-refresh is still there and reports its own failure.
      await tester.fling(_feedList.first, const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      expect(find.text('Could not load this section'), findsOneWidget);
      expect(_story('a'), findsOneWidget);
    });

    testWidgets('further down: the position stays, no button, no message',
        (tester) async {
      final server = _FeedServer(_ids('p', 30));
      final h = await _pumpFeed(tester, server);
      await _scrollDown(tester, 2500);
      final offset = _scroll(tester).pixels;
      server.offline = true;

      h.awayFor(const Duration(minutes: 10));
      await tester.pumpAndSettle();
      expect(_scroll(tester).pixels, offset);
      expect(_newPosts, findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    });
  });
}
