import 'authenticated_onboarding_store.dart';

AuthenticatedOnboardingStore createPlatformAuthenticatedOnboardingStore() {
  return FlutterSecureAuthenticatedOnboardingStore();
}
