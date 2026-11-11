// EMU-103: leaderboard counts use the grammatical form for the number
// ("1 post", not "1 posts") in English, Russian and Uzbek.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mushukistan_frontend/core/localization/app_strings.dart';
import 'package:mushukistan_frontend/core/localization/language_controller.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';
import 'package:mushukistan_frontend/features/leaderboards/presentation/screens/leaderboard_screen.dart';

import '../../support/fakes.dart';

const _numbers = [0, 1, 2, 5, 11, 21, 22, 25, 101];

LeaderboardEntryData _entry(int rank, int posts, int likes) =>
    LeaderboardEntryData(
      rank: rank,
      user: LeaderboardUserData(
          id: 'user-$rank', name: 'User $rank', avatarUrl: null),
      observationCount: posts,
      likeCount: likes,
    );

Future<void> _pump(
  WidgetTester tester, {
  required List<LeaderboardEntryData> entries,
  String type = 'most_active',
  AppLanguage language = AppLanguage.english,
}) async {
  tester.view.physicalSize = const Size(390, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(overrides: [
    leaderboardProvider.overrideWith((ref) async => entries),
    appLanguageProvider.overrideWith((ref) => language),
  ]);
  container.read(leaderboardTypeProvider.notifier).state = type;
  addTearDown(container.dispose);
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, __) => const LeaderboardScreen()),
    GoRoute(
      path: '/users/:id',
      builder: (_, s) => Text('Profile ${s.pathParameters['id']}'),
    ),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
}

void main() {
  final en = AppStrings.forLanguage(AppLanguage.english);
  final ru = AppStrings.forLanguage(AppLanguage.russian);
  final uz = AppStrings.forLanguage(AppLanguage.uzbek);

  test('English: singular only for exactly one', () {
    expect([
      for (final n in _numbers) en.postCount(n)
    ], [
      '0 posts',
      '1 post',
      '2 posts',
      '5 posts',
      '11 posts',
      '21 posts',
      '22 posts',
      '25 posts',
      '101 posts',
    ]);
    expect(en.likeCount(1), '1 like');
    expect(en.likeCount(0), '0 likes');
    expect(en.likeCount(21), '21 likes');
  });

  test('Russian: one / few / many forms', () {
    expect([
      for (final n in _numbers) ru.postCount(n)
    ], [
      '0 постов',
      '1 пост',
      '2 поста',
      '5 постов',
      '11 постов',
      '21 пост',
      '22 поста',
      '25 постов',
      '101 пост',
    ]);
    expect([
      for (final n in _numbers) ru.likeCount(n)
    ], [
      '0 лайков',
      '1 лайк',
      '2 лайка',
      '5 лайков',
      '11 лайков',
      '21 лайк',
      '22 лайка',
      '25 лайков',
      '101 лайк',
    ]);
    expect(ru.postCount(12), '12 постов');
    expect(ru.postCount(14), '14 постов');
    expect(ru.postCount(111), '111 постов');
    expect(ru.postCount(112), '112 постов');
    expect(ru.postCount(1004), '1004 поста');
  });

  test('Uzbek: the noun stays singular after a number', () {
    expect([for (final n in _numbers) uz.postCount(n)],
        [for (final n in _numbers) '$n ta post']);
    expect([for (final n in _numbers) uz.likeCount(n)],
        [for (final n in _numbers) '$n ta layk']);
  });

  testWidgets('Active leaderboard shows "1 post" and "2 posts" in order',
      (tester) async {
    await _pump(tester, entries: [
      _entry(1, 2, 10),
      _entry(2, 1, 4),
      _entry(3, 1, 0),
    ]);
    expect(find.text('2 posts'), findsOneWidget);
    expect(find.text('1 post'), findsNWidgets(2));
    expect(find.text('1 posts'), findsNothing);
    // Ranking order is unchanged.
    final first = tester.getTopLeft(find.text('User 1')).dy;
    final second = tester.getTopLeft(find.text('User 2')).dy;
    final third = tester.getTopLeft(find.text('User 3')).dy;
    expect(first, lessThan(second));
    expect(second, lessThan(third));
    // Rows still open the profile.
    await tester.tap(find.text('User 2'));
    await tester.pumpAndSettle();
    expect(find.text('Profile user-2'), findsOneWidget);
  });

  testWidgets('Popular leaderboard shows "1 like"', (tester) async {
    await _pump(tester,
        type: 'most_popular', entries: [_entry(1, 3, 2), _entry(2, 3, 1)]);
    expect(find.text('2 likes'), findsOneWidget);
    expect(find.text('1 like'), findsOneWidget);
    expect(find.text('1 likes'), findsNothing);
  });

  testWidgets('Russian and Uzbek rows use their forms', (tester) async {
    await _pump(tester,
        language: AppLanguage.russian,
        entries: [_entry(1, 21, 0), _entry(2, 3, 0), _entry(3, 5, 0)]);
    expect(find.text('21 пост'), findsOneWidget);
    expect(find.text('3 поста'), findsOneWidget);
    expect(find.text('5 постов'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await _pump(tester,
        language: AppLanguage.uzbek, entries: [_entry(1, 1, 0)]);
    expect(find.text('1 ta post'), findsOneWidget);
  });

  test('leaderboard requests only the top 10', () async {
    final client = FakeApiClient()
      ..setHandler('GET', 'leaderboards/most_active', (_) => <Object?>[]);
    final container = ProviderContainer(overrides: [
      mushukistanApiProvider.overrideWithValue(MushukistanApi(client: client)),
    ]);
    addTearDown(container.dispose);
    final sub = container.listen(leaderboardProvider, (_, __) {});
    addTearDown(sub.close);
    await container.read(leaderboardProvider.future);
    expect(client.calls.single.queryParameters?['limit'], 10);
  });
}
