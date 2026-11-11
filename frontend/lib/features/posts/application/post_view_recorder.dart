import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/mushukistan_api.dart';
import '../../auth/application/auth_controller.dart';

/// API path segments of the three post kinds that count views.
abstract final class PostViewCollection {
  static const observation = 'posts';
  static const lostPet = 'lost-pets';
  static const adoption = 'adoption-posts';

  /// The `kind` the batch endpoint expects for each path segment.
  static const _kinds = <String, String>{
    observation: 'post',
    lostPet: 'lost_pet',
    adoption: 'adoption',
  };
  static const _collections = <String, String>{
    'post': observation,
    'lost_pet': lostPet,
    'adoption': adoption,
  };
}

/// Key of a post in [postViewCountsProvider]: `'<collection>/<id>'`.
String postViewKey(String collection, String id) => '$collection/$id';

/// Latest view counts the server returned during this app session.
///
/// Feed cards and post pages show the larger of this and the count they
/// loaded, so a view recorded here appears without reloading the feed.
final postViewCountsProvider = StateProvider<Map<String, int>>(
  (ref) => const {},
);

/// The count to show for a post: the loaded one, or a newer one from the server.
int liveViewCount(WidgetRef ref, String collection, String id, int loaded) {
  final latest = ref.watch(
    postViewCountsProvider
        .select((counts) => counts[postViewKey(collection, id)]),
  );
  return latest == null ? loaded : max(latest, loaded);
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
  final recorder = PostViewRecorder(
    api: ref.watch(mushukistanApiProvider),
    storage: PreferencesViewerIdStorage(),
    signedIn: () => ref.read(authControllerProvider).isAuthenticated,
    onCount: (key, count) {
      final counts = ref.read(postViewCountsProvider.notifier);
      if (counts.state[key] == count) return;
      counts.state = {...counts.state, key: count};
    },
  );
  // Send queued cards when the app goes to the background or the browser tab
  // is hidden, so they are not lost if the app is then closed.
  final lifecycle = _FlushWhenHidden(recorder);
  WidgetsBinding.instance.addObserver(lifecycle);
  ref.onDispose(() {
    WidgetsBinding.instance.removeObserver(lifecycle);
    recorder.dispose();
  });
  return recorder;
});

class _FlushWhenHidden with WidgetsBindingObserver {
  _FlushWhenHidden(this.recorder);

  final PostViewRecorder recorder;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(recorder.flush());
    }
  }
}

/// Tells the server which posts this viewer opened or saw (docs/ADRS.md, ADR-0024).
///
/// Opening a post page is sent at once. Feed cards that were on screen long
/// enough are queued and sent together. Each post is reported at most once per
/// app session, whichever happens first; the server also counts each person
/// once per post. Signed-in viewers are counted by account. Guests send a
/// random id kept on this device, created on first use and never linked to an
/// account. Failures are ignored because a missed view must never disturb
/// reading; a failed post can be reported again later.
class PostViewRecorder {
  PostViewRecorder({
    required MushukistanApi api,
    required ViewerIdStorage storage,
    required bool Function() signedIn,
    void Function(String key, int count)? onCount,
    Random? random,
    this.batchDelay = const Duration(seconds: 10),
    this.maxBatch = 20,
  })  : _api = api,
        _storage = storage,
        _signedIn = signedIn,
        _onCount = onCount,
        _random = random ?? Random.secure();

  final MushukistanApi _api;
  final ViewerIdStorage _storage;
  final bool Function() _signedIn;
  final void Function(String key, int count)? _onCount;
  final Random _random;

  /// How long seen feed cards wait so they can be sent together. Long enough
  /// that view reports use few of the API's per-minute request allowance,
  /// which they share with likes, comments and post pages.
  final Duration batchDelay;

  /// Seen feed cards sent in one request at most (the server allows 50).
  final int maxBatch;

  final Set<String> _reported = <String>{};
  final List<(String, String)> _pending = <(String, String)>[];
  Timer? _flushTimer;
  bool _disposed = false;
  Future<String>? _guestId;

  /// A post page was opened.
  Future<void> record(String collection, String id) async {
    final key = postViewKey(collection, id);
    if (!_reported.add(key)) return;
    try {
      final count = await _api.recordPostView(
        collection,
        id,
        guestViewerId: await _guestIdIfNeeded(),
      );
      _onCount?.call(key, count);
    } catch (_) {
      _reported.remove(key);
    }
  }

  /// A feed card for this post was on screen long enough to count as seen.
  void markSeen(String collection, String id) {
    if (_disposed) return;
    if (!PostViewCollection._kinds.containsKey(collection)) return;
    if (!_reported.add(postViewKey(collection, id))) return;
    _pending.add((collection, id));
    if (_pending.length >= maxBatch) {
      unawaited(flush());
    } else {
      _flushTimer ??= Timer(batchDelay, () => unawaited(flush()));
    }
  }

  /// Sends the queued seen cards now.
  Future<void> flush() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (_pending.isEmpty) return;
    final batch = List<(String, String)>.of(_pending.take(maxBatch));
    _pending.removeRange(0, batch.length);
    if (_pending.isNotEmpty && !_disposed) {
      _flushTimer = Timer(batchDelay, () => unawaited(flush()));
    }
    try {
      final results = await _api.recordSeenPosts(
        [
          for (final (collection, id) in batch)
            (kind: PostViewCollection._kinds[collection]!, id: id),
        ],
        guestViewerId: await _guestIdIfNeeded(),
      );
      for (final result in results) {
        final collection = PostViewCollection._collections[result.kind];
        if (collection == null) continue;
        _onCount?.call(postViewKey(collection, result.id), result.viewCount);
      }
    } catch (_) {
      for (final (collection, id) in batch) {
        _reported.remove(postViewKey(collection, id));
      }
    }
  }

  /// Sends what is queued, best effort, and stops accepting new cards.
  void dispose() {
    _disposed = true;
    unawaited(flush());
  }

  /// One shared lookup, so concurrent first reports cannot create two ids.
  Future<String?> _guestIdIfNeeded() async {
    if (_signedIn()) return null;
    final pending = _guestId ??= _guestViewerId();
    try {
      return await pending;
    } catch (_) {
      if (identical(_guestId, pending)) _guestId = null;
      rethrow;
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
