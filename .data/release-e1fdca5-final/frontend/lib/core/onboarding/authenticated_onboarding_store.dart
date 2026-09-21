import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'authenticated_onboarding_store_factory.dart';

final authenticatedOnboardingStoreProvider =
    Provider<AuthenticatedOnboardingStore>((ref) {
  return createAuthenticatedOnboardingStore();
});

abstract class AuthenticatedOnboardingStore {
  Future<bool> hasSeen(String userId);
  Future<void> markSeen(String userId);
}

class FlutterSecureAuthenticatedOnboardingStore
    implements AuthenticatedOnboardingStore {
  FlutterSecureAuthenticatedOnboardingStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _keyPrefix = 'mushukistan_authenticated_onboarding_seen_';

  final FlutterSecureStorage _storage;

  @override
  Future<bool> hasSeen(String userId) async {
    return await _storage.read(key: '$_keyPrefix$userId') == 'true';
  }

  @override
  Future<void> markSeen(String userId) {
    return _storage.write(key: '$_keyPrefix$userId', value: 'true');
  }
}

class InMemoryAuthenticatedOnboardingStore
    implements AuthenticatedOnboardingStore {
  InMemoryAuthenticatedOnboardingStore({Set<String>? seenUserIds})
      : _seenUserIds = seenUserIds ?? <String>{};

  final Set<String> _seenUserIds;

  @override
  Future<bool> hasSeen(String userId) async {
    return _seenUserIds.contains(userId);
  }

  @override
  Future<void> markSeen(String userId) async {
    _seenUserIds.add(userId);
  }
}
