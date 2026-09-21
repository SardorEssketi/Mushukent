import 'package:web/web.dart' as web;

import 'authenticated_onboarding_store.dart';

class WebLocalAuthenticatedOnboardingStore
    implements AuthenticatedOnboardingStore {
  static const _keyPrefix = 'mushukistan_authenticated_onboarding_seen_';

  @override
  Future<bool> hasSeen(String userId) async {
    return web.window.localStorage.getItem('$_keyPrefix$userId') == 'true';
  }

  @override
  Future<void> markSeen(String userId) async {
    web.window.localStorage.setItem('$_keyPrefix$userId', 'true');
  }
}

AuthenticatedOnboardingStore createPlatformAuthenticatedOnboardingStore() {
  return WebLocalAuthenticatedOnboardingStore();
}
