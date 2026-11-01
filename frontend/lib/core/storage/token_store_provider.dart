import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'token_store.dart';
import 'token_store_factory.dart';

final tokenStoreProvider = Provider<AuthTokenStore>((ref) {
  final store = GuardedAuthTokenStore(createAuthTokenStore());
  ref.onDispose(store.dispose);
  return store;
});
