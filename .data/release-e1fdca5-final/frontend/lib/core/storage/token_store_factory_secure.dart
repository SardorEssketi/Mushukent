import 'flutter_secure_token_store.dart';
import 'token_store.dart';

AuthTokenStore createPlatformAuthTokenStore() {
  return FlutterSecureTokenStore();
}
