// The card that opens from a cat or Lost Pet marker previews the post:
// photo, title, date, author, text and counts.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';
import 'package:mushukistan_frontend/core/widgets/app_remote_image.dart';
import 'package:mushukistan_frontend/features/map/presentation/screens/map_screen.dart';

import 'package:mushukistan_frontend/features/posts/application/post_view_recorder.dart';

import '../../support/fakes.dart';

const _empty = {'items': <Object>[], 'next_cursor': null, 'limit': 100};

FakeApiClient _client({Object? cats, Object? lostPets}) {
  return FakeApiClient()
    ..setHandler('GET', 'cats', (_) => cats ?? _empty)
    ..setHandler('GET', 'places', (_) => _empty)
    ..setHandler('GET', 'lost-pets/map', (_) => lostPets ?? _empty);
}

Future<void> _pumpMap(WidgetTester tester, FakeApiClient client) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      mushukistanApiProvider.overrideWithValue(MushukistanApi(client: client)),
    ],
    child: const MaterialApp(home: MapScreen()),
  ));
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump();
}

Map<String, Object?> _cats({String? name}) => {
      'items': [
        {
          'id': 'cat-1',
          'name': name,
          'status': 'active',
          'total_observations': 2,
          'cover_photo_url': 'https://example.com/cover.jpg',
          'canonical_location': {'latitude': 41.3, 'longitude': 69.25},
          'last_seen_at': '2026-11-07T09:00:00Z',
          'latest_post_kind': 'observation',
        }
      ],
      'next_cursor': null,
      'limit': 100,
    };

const _catPosts = {
  'items': [
    {
      'id': 'post-9',
      'cat': {'id': 'cat-1'},
      'author': {'id': 'u1', 'name': 'Dilnoza'},
      'photo_url': 'https://example.com/photo.jpg',
      'description': 'Grey cat by the bakery, very friendly.',
      'created_at': '2026-11-07T09:00:00Z',
      'like_count': 4,
      'comment_count': 2,
      'view_count': 31,
      'is_liked_by_me': false,
    }
  ],
  'next_cursor': null,
  'limit': 1,
};

const _lostPets = {
  'items': [
    {
      'id': 'pet-1',
      'pet_name': 'Mittens',
      'last_seen_location': {'latitude': 41.3, 'longitude': 69.25},
      'is_resolved': false,
      'created_at': '2026-09-28T09:00:00Z',
    }
  ],
  'next_cursor': null,
  'limit': 100,
};

void main() {
  testWidgets("a cat marker's card previews the cat's newest post",
      (tester) async {
    final client = _client(cats: _cats())
      ..setHandler('GET', 'cats/cat-1/posts', (_) => _catPosts);
    await _pumpMap(tester, client);

    await tester.tap(find.byKey(const ValueKey('marker:observations:cat-1')));
    await tester.pumpAndSettle();

    // The kind of post is said once, not as both title and subtitle.
    expect(find.text('Cat post'), findsOneWidget);
    expect(find.text('Observation'), findsNothing);
    expect(find.text('Grey cat by the bakery, very friendly.'), findsOneWidget);
    expect(find.textContaining('Nov 7, 2026'), findsOneWidget);
    expect(find.textContaining('Dilnoza'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('31'), findsOneWidget);
    expect(find.text('Open post'), findsOneWidget);
    // The post's own photo, not the cat's cover photo.
    expect(
      tester.widget<AppRemoteImage>(find.byType(AppRemoteImage)).url,
      'https://example.com/photo.jpg',
    );
    // A view recorded in this session shows without reopening the card.
    ProviderScope.containerOf(tester.element(find.text('31')))
        .read(postViewCountsProvider.notifier)
        .state = {postViewKey(PostViewCollection.observation, 'post-9'): 32};
    await tester.pump();
    expect(find.text('32'), findsOneWidget);
    // One lookup feeds both the preview and the button.
    expect(
      client.calls.where((call) => call.path == 'cats/cat-1/posts'),
      hasLength(1),
    );
  });

  testWidgets('the card still opens when the post cannot be loaded',
      (tester) async {
    final client = _client(cats: _cats(name: 'Barsik'))
      ..setHandler('GET', 'cats/cat-1/posts',
          (_) => throw StateError('Posts unavailable'));
    await _pumpMap(tester, client);

    await tester.tap(find.byKey(const ValueKey('marker:observations:cat-1')));
    await tester.pumpAndSettle();

    expect(find.text('Barsik'), findsOneWidget);
    expect(find.textContaining('Nov 7, 2026'), findsOneWidget);
    expect(find.text('Open post'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets("a Lost Pet marker's card previews that post", (tester) async {
    final client = _client(lostPets: _lostPets)
      ..setHandler(
          'GET',
          'lost-pets/pet-1',
          (_) => {
                'id': 'pet-1',
                'pet_name': 'Mittens',
                'author': {'id': 'u2', 'name': 'Timur'},
                'photo_url': 'https://example.com/photo.jpg',
                'photo_urls': ['https://example.com/photo.jpg'],
                'additional_info': 'White paws, blue collar.',
                'last_seen_location': {'latitude': 41.3, 'longitude': 69.25},
                'created_at': '2026-09-28T09:00:00Z',
                'is_resolved': false,
                'comment_count': 3,
                'view_count': 12,
              });
    await _pumpMap(tester, client);

    await tester.tap(find.byKey(const ValueKey('marker:lostPets:pet-1')));
    await tester.pumpAndSettle();

    expect(find.text('Mittens'), findsOneWidget);
    expect(find.text('White paws, blue collar.'), findsOneWidget);
    expect(find.textContaining('Sep 28, 2026'), findsOneWidget);
    expect(find.textContaining('Timur'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('Open post'), findsOneWidget);
  });
}
