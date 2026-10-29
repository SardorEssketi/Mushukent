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

void main() {
  late FakeApiClient client;
  late _MemoryViewerIdStorage storage;
  late PostViewRecorder recorder;

  setUp(() {
    client = FakeApiClient();
    storage = _MemoryViewerIdStorage();
    recorder = PostViewRecorder(
      api: MushukistanApi(client: client),
      storage: storage,
    );
    for (final path in [
      'posts/p1/views',
      'lost-pets/l1/views',
      'adoption-posts/a1/views',
    ]) {
      client.setHandler(
          'POST', path, (_) => {'view_count': 3, 'counted': true});
    }
  });

  test('guests send one stable random id, created once', () async {
    await recorder.record(PostViewCollection.observation, 'p1',
        signedIn: false);
    await recorder.record(PostViewCollection.lostPet, 'l1', signedIn: false);

    final ids = client.calls.map((call) => call.headers?['X-Viewer-Id']);
    expect(ids.toSet(), hasLength(1));
    expect(
      ids.first,
      matches(RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')),
    );
    expect(storage.writes, 1);
  });

  test('signed-in viewers never send the guest id', () async {
    await recorder.record(PostViewCollection.adoption, 'a1', signedIn: true);

    expect(client.calls.single.path, 'adoption-posts/a1/views');
    expect(client.calls.single.headers, isNull);
    expect(storage.writes, 0);
  });

  test('each post is reported once per session, retried after a failure',
      () async {
    await recorder.record(PostViewCollection.observation, 'p1', signedIn: true);
    await recorder.record(PostViewCollection.observation, 'p1', signedIn: true);
    expect(client.calls, hasLength(1));

    client.setHandler(
        'POST', 'lost-pets/l1/views', (_) => throw StateError('offline'));
    await recorder.record(PostViewCollection.lostPet, 'l1', signedIn: true);
    client.setHandler('POST', 'lost-pets/l1/views', (_) => {'view_count': 1});
    await recorder.record(PostViewCollection.lostPet, 'l1', signedIn: true);
    expect(client.calls.where((c) => c.path == 'lost-pets/l1/views'),
        hasLength(2));
  });
}
