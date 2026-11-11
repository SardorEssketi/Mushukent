import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';
import 'package:mushukistan_frontend/features/posts/application/post_view_recorder.dart';

import '../../support/fakes.dart';

class _MemoryViewerIdStorage implements ViewerIdStorage {
  String? value;
  int writes = 0;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async {
    this.value = value;
    writes++;
  }
}

const _delay = Duration(milliseconds: 60);

/// Waits past the batch delay so queued cards are sent and answered.
Future<void> _settle() => Future<void>.delayed(_delay * 2);

void main() {
  late FakeApiClient client;
  late _MemoryViewerIdStorage storage;
  late bool signedIn;
  late Map<String, int> counts;
  late PostViewRecorder recorder;

  setUp(() {
    client = FakeApiClient();
    storage = _MemoryViewerIdStorage();
    signedIn = false;
    counts = {};
    recorder = PostViewRecorder(
      api: MushukistanApi(client: client),
      storage: storage,
      signedIn: () => signedIn,
      onCount: (key, count) => counts[key] = count,
      maxBatch: 3,
      batchDelay: _delay,
    );
    for (final path in [
      'posts/p1/views',
      'lost-pets/l1/views',
      'adoption-posts/a1/views',
    ]) {
      client.setHandler(
          'POST', path, (_) => {'view_count': 3, 'counted': true});
    }
    client.setHandler('POST', 'views/seen', (call) {
      final items = (call.body! as Map)['items'] as List;
      return {
        'items': [
          for (final item in items)
            {...(item as Map), 'view_count': 7, 'counted': true},
        ],
      };
    });
  });

  List<ApiCall> seenCalls() =>
      client.calls.where((c) => c.path == 'views/seen').toList();

  test('guests send one stable random id, created once', () async {
    await recorder.record(PostViewCollection.observation, 'p1');
    await recorder.record(PostViewCollection.lostPet, 'l1');

    final ids = client.calls.map((call) => call.headers?['X-Viewer-Id']);
    expect(ids.toSet(), hasLength(1));
    expect(
      ids.first,
      matches(RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')),
    );
    expect(storage.writes, 1);
  });

  test('concurrent first reports share one new guest id', () async {
    await Future.wait([
      recorder.record(PostViewCollection.observation, 'p1'),
      recorder.record(PostViewCollection.lostPet, 'l1'),
    ]);

    final ids = client.calls.map((call) => call.headers?['X-Viewer-Id']);
    expect(ids.toSet(), hasLength(1));
    expect(storage.writes, 1);
  });

  test('signed-in viewers never send the guest id', () async {
    signedIn = true;
    await recorder.record(PostViewCollection.adoption, 'a1');

    expect(client.calls.single.path, 'adoption-posts/a1/views');
    expect(client.calls.single.headers, isNull);
    expect(storage.writes, 0);
    expect(counts, {'adoption-posts/a1': 3});
  });

  test('each post is reported once per session, retried after a failure',
      () async {
    await recorder.record(PostViewCollection.observation, 'p1');
    await recorder.record(PostViewCollection.observation, 'p1');
    expect(client.calls, hasLength(1));

    client.setHandler(
        'POST', 'lost-pets/l1/views', (_) => throw StateError('offline'));
    await recorder.record(PostViewCollection.lostPet, 'l1');
    client.setHandler('POST', 'lost-pets/l1/views', (_) => {'view_count': 1});
    await recorder.record(PostViewCollection.lostPet, 'l1');
    expect(client.calls.where((c) => c.path == 'lost-pets/l1/views'),
        hasLength(2));
  });

  test('seen feed cards are sent together after a short wait', () async {
    signedIn = true;
    recorder.markSeen(PostViewCollection.observation, 'p1');
    recorder.markSeen(PostViewCollection.lostPet, 'l1');
    recorder.markSeen(PostViewCollection.lostPet, 'l1');
    await Future<void>.delayed(_delay ~/ 3);
    expect(seenCalls(), isEmpty);

    await _settle();
    expect(seenCalls().single.headers, isNull);
    expect(seenCalls().single.body, {
      'items': [
        {'kind': 'post', 'id': 'p1'},
        {'kind': 'lost_pet', 'id': 'l1'},
      ],
    });
    expect(counts, {'posts/p1': 7, 'lost-pets/l1': 7});
  });

  test('a full batch is sent at once and the rest follows', () async {
    for (final id in ['a', 'b', 'c', 'd']) {
      recorder.markSeen(PostViewCollection.observation, id);
    }
    await Future<void>.delayed(Duration.zero);
    expect(seenCalls(), hasLength(1));
    expect((seenCalls().single.body! as Map)['items'], hasLength(3));

    await _settle();
    expect(seenCalls(), hasLength(2));
    expect((seenCalls().last.body! as Map)['items'], [
      {'kind': 'post', 'id': 'd'},
    ]);
    expect(seenCalls().first.headers?['X-Viewer-Id'], isNotNull);
  });

  test('a post seen in the feed is not reported again when opened', () async {
    recorder.markSeen(PostViewCollection.observation, 'p1');
    await _settle();
    await recorder.record(PostViewCollection.observation, 'p1');

    expect(client.calls.map((c) => c.path), ['views/seen']);
  });

  test('a failed batch can be seen again', () async {
    client.setHandler('POST', 'views/seen', (_) => throw StateError('x'));
    recorder.markSeen(PostViewCollection.adoption, 'a1');
    await _settle();

    client.setHandler('POST', 'views/seen', (_) => {'items': []});
    recorder.markSeen(PostViewCollection.adoption, 'a1');
    await _settle();
    expect(seenCalls(), hasLength(2));
  });

  test('dispose sends what is queued and ignores later cards', () async {
    recorder.markSeen(PostViewCollection.observation, 'p1');
    recorder.dispose();
    recorder.markSeen(PostViewCollection.observation, 'p2');
    await _settle();

    expect(seenCalls(), hasLength(1));
    expect((seenCalls().single.body! as Map)['items'], [
      {'kind': 'post', 'id': 'p1'},
    ]);
  });
}
