import 'token_store.dart';
import 'token_store_factory_secure.dart'
    if (dart.library.html) 'token_store_factory_web.dart';

AuthTokenStore createAuthTokenStore() {
  return createPlatformAuthTokenStore();
}
