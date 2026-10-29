import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/mushukistan_api.dart';

/// API path segments of the three post kinds that count views.
abstract final class PostViewCollection {
  static const observation = 'posts';
  static const lostPet = 'lost-pets';
  static const adoption = 'adoption-posts';
}

abstract class ViewerIdStorage {
  Future<String?> read();
  Future<void> write(String value);
}

class PreferencesViewerIdStorage implements ViewerIdStorage {
  static const _key = 'guest_viewer_id_v1';
  SharedPreferencesAsync? _preferences;
  SharedPreferencesAsync get _store =>
      _preferences ??= SharedPreferencesAsync();

  @override
  Future<String?> read() => _store.getString(_key);

  @override
  Future<void> write(String value) => _store.setString(_key, value);
}

final postViewRecorderProvider = Provider<PostViewRecorder>((ref) {
  return PostViewRecorder(
    api: ref.watch(mushukistanApiProvider),
    storage: PreferencesViewerIdStorage(),
  );
});

/// Tells the server a post page was opened (docs/ADRS.md, ADR-0024).
///
/// Signed-in viewers are counted by account. Guests send a random id kept on
/// this device, created on first use and never linked to an account. Each post
/// is reported at most once per app session; failures are ignored because a
/// missed view must never disturb reading the post.
class PostViewRecorder {
  PostViewRecorder({
    required MushukistanApi api,
    required ViewerIdStorage storage,
    Random? random,
  })  : _api = api,
        _storage = storage,
        _random = random ?? Random.secure();

  final MushukistanApi _api;
  final ViewerIdStorage _storage;
  final Random _random;
  final Set<String> _reported = <String>{};

  Future<void> record(
    String collection,
    String id, {
    required bool signedIn,
  }) async {
    if (!_reported.add('$collection/$id')) return;
    try {
      await _api.recordPostView(
        collection,
        id,
        guestViewerId: signedIn ? null : await _guestViewerId(),
      );
    } catch (_) {
      _reported.remove('$collection/$id');
    }
  }

  Future<String> _guestViewerId() async {
    final saved = await _storage.read();
    if (saved != null && _uuidPattern.hasMatch(saved)) return saved;
    final created = _randomUuidV4();
    await _storage.write(created);
    return created;
  }

  String _randomUuidV4() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  static final _uuidPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );
}
