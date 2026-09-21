import 'authenticated_onboarding_store.dart';
import 'authenticated_onboarding_store_factory_secure.dart'
    if (dart.library.html) 'authenticated_onboarding_store_factory_web.dart';

AuthenticatedOnboardingStore createAuthenticatedOnboardingStore() {
  return createPlatformAuthenticatedOnboardingStore();
}
