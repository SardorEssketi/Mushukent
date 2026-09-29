import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';
import 'package:mushukistan_frontend/features/leaderboards/presentation/screens/leaderboard_screen.dart';

void main() {
  test('leaderboard defaults to the month period', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(leaderboardPeriodProvider), 'month');
  });

  test('leaderboard API model preserves its metrics as separate values', () {
    final entry = LeaderboardEntryData.fromJson({
      'rank': 4,
      'user': {
        'id': 'user-4',
        'name': 'Sardor Muxtorov',
        'avatar_url': null,
      },
      'observation_count': 37,
      'like_count': 184,
    });

    expect(entry.observationCount, 37);
    expect(entry.likeCount, 184);
    expect(entry.user.id, 'user-4');
  });

  testWidgets('active shows observations and profile rows remain tappable', (
    tester,
  ) async {
    await _setWidth(tester, 390);
    await _pumpLeaderboard(tester, entries: _entries);

    expect(find.text('37 observations'), findsOneWidget);
    expect(find.text('184 likes'), findsNothing);
    expect(find.text('Score'), findsNothing);
    expect(find.text('Top helpers'), findsNothing);
    expect(find.text('This month'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Sardor Muxtorov'));
    await tester.pumpAndSettle();
    expect(find.text('Profile user-4'), findsOneWidget);
  });

  testWidgets('popular shows likes without observations', (tester) async {
    await _setWidth(tester, 1000);
    await _pumpLeaderboard(
      tester,
      type: 'most_popular',
      entries: _entries.take(1).toList(growable: false),
    );

    expect(find.text('184 likes'), findsOneWidget);
    expect(find.text('37 observations'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty leaderboard shows its empty state', (tester) async {
    await _pumpLeaderboard(tester, entries: const []);

    expect(find.text('No leaderboard data yet.'), findsOneWidget);
  });

  testWidgets('pending request shows the loading state', (tester) async {
    final result = Completer<List<LeaderboardEntryData>>();
    await _pumpLeaderboard(tester, result: result.future, settle: false);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    result.complete(_entries);
    await tester.pumpAndSettle();
    expect(find.text('37 observations'), findsOneWidget);
  });

  testWidgets('failed request shows retry state', (tester) async {
    await _pumpLeaderboard(tester, error: StateError('test error'));

    expect(find.text('Could not load this section'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}

const _entries = <LeaderboardEntryData>[
  LeaderboardEntryData(
    rank: 1,
    user: LeaderboardUserData(
      id: 'user-1',
      name: 'Alice Example',
      avatarUrl: null,
    ),
    observationCount: 37,
    likeCount: 184,
  ),
  LeaderboardEntryData(
    rank: 2,
    user: LeaderboardUserData(
      id: 'user-2',
      name: 'Bob Example',
      avatarUrl: null,
    ),
    observationCount: 26,
    likeCount: 90,
  ),
  LeaderboardEntryData(
    rank: 3,
    user: LeaderboardUserData(
      id: 'user-3',
      name: 'Charlie Example',
      avatarUrl: null,
    ),
    observationCount: 19,
    likeCount: 68,
  ),
  LeaderboardEntryData(
    rank: 4,
    user: LeaderboardUserData(
      id: 'user-4',
      name: 'Sardor Muxtorov',
      avatarUrl: null,
    ),
    observationCount: 12,
    likeCount: 41,
  ),
];

Future<void> _pumpLeaderboard(
  WidgetTester tester, {
  List<LeaderboardEntryData> entries = const [],
  Future<List<LeaderboardEntryData>>? result,
  String type = 'most_active',
  Object? error,
  bool settle = true,
}) async {
  final container = ProviderContainer(
    overrides: [
      leaderboardProvider.overrideWith((ref) {
        if (result != null) {
          return result;
        }
        if (error != null) {
          return Future<List<LeaderboardEntryData>>.error(error);
        }
        return Future<List<LeaderboardEntryData>>.value(entries);
      }),
    ],
  );
  container.read(leaderboardTypeProvider.notifier).state = type;
  addTearDown(container.dispose);

  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const LeaderboardScreen(),
      ),
      GoRoute(
        path: '/users/:userId',
        builder: (context, state) => Scaffold(
          body: Text('Profile ${state.pathParameters['userId']}'),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<void> _setWidth(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
