import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Remembers on this device that the feed introduction was closed.
abstract class FeedIntroStorage {
  Future<bool> isDismissed();
  Future<void> dismiss();
}

class PreferencesFeedIntroStorage implements FeedIntroStorage {
  static const _key = 'feed_intro_dismissed_v1';
  SharedPreferencesAsync? _preferences;
  SharedPreferencesAsync get _store =>
      _preferences ??= SharedPreferencesAsync();

  @override
  Future<bool> isDismissed() async {
    try {
      return await _store.getBool(_key) ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> dismiss() async {
    try {
      await _store.setBool(_key, true);
    } catch (_) {
      // Unavailable storage only means the card may return next launch.
    }
  }
}

final feedIntroStorageProvider =
    Provider<FeedIntroStorage>((ref) => PreferencesFeedIntroStorage());

/// `null` while the saved choice loads, so the card never flashes.
final feedIntroDismissedProvider =
    StateNotifierProvider<FeedIntroController, bool?>((ref) {
  return FeedIntroController(ref.watch(feedIntroStorageProvider));
});

class FeedIntroController extends StateNotifier<bool?> {
  FeedIntroController(this._storage) : super(null) {
    _storage.isDismissed().then((dismissed) {
      if (mounted && state == null) state = dismissed;
    });
  }

  final FeedIntroStorage _storage;

  Future<void> dismiss() async {
    state = true;
    await _storage.dismiss();
  }
}
