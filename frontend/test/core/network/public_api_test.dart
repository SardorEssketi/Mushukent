import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';

import '../../support/fakes.dart';

void main() {
  test('public feed and post reads do not require restored credentials',
      () async {
    final client = FakeApiClient();
    client.setHandler('GET', 'feed', (_) {
      return <String, Object?>{
        'items': <Object?>[],
        'next_cursor': null,
        'limit': 20,
      };
    });
    client.setHandler('GET', 'posts/post-1', (_) {
      return <String, Object?>{
        'id': 'post-1',
        'cat': <String, Object?>{
          'id': 'cat-1',
          'name': 'Mushu',
          'status': 'healthy',
          'cover_photo_url': null,
        },
        'photo_url': 'https://example.com/cat.jpg',
        'photo_urls': <String>['https://example.com/cat.jpg'],
        'location': null,
        'created_at': '2026-09-21T10:00:00Z',
        'like_count': 0,
        'comment_count': 0,
        'is_liked_by_me': false,
      };
    });
    final api = MushukistanApi(client: client);

    await api.listFeed(includeViewerContext: false);
    await api.getPost('post-1', includeViewerContext: false);

    expect(client.calls, hasLength(2));
    expect(client.calls.every((call) => !call.authenticated), isTrue);
  });
}
