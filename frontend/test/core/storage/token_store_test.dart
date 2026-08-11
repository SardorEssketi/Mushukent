import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/core/storage/token_store.dart';

void main() {
  test('in-memory token store writes reads and deletes tokens', () async {
    final store = InMemoryAuthTokenStore();

    expect(await store.read(), isNull);
    await store.write('token-123');
    expect(await store.read(), 'token-123');
    await store.delete();
    expect(await store.read(), isNull);
  });
}
