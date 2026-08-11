import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'token_store.dart';
import 'token_store_factory.dart';

final tokenStoreProvider = Provider<AuthTokenStore>((ref) {
  return createAuthTokenStore();
});
