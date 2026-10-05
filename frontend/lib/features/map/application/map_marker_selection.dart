import 'package:flutter/foundation.dart';

/// Each pin listens only to its own selected state. Selecting one pin changes
/// at most the previous and the next pin instead of rebuilding every marker.
class MapMarkerSelection {
  final _selectedByKey = <String, ValueNotifier<bool>>{};
  Set<String> _retainedKeys = const {};
  String? _selectedKey;

  ValueListenable<bool> listenableFor(String key) =>
      _selectedByKey.putIfAbsent(key, () => ValueNotifier(false));

  void select(String key) {
    if (_selectedKey == key) return;
    final previous = _selectedKey;
    _selectedKey = key;
    if (previous != null) _selectedByKey[previous]?.value = false;
    _selectedByKey.putIfAbsent(key, () => ValueNotifier(false)).value = true;
  }

  void clearIfSelected(String key) {
    if (_selectedKey != key) return;
    _selectedKey = null;
    _selectedByKey[key]?.value = false;
    if (!_retainedKeys.contains(key)) _selectedByKey.remove(key)?.dispose();
  }

  void retainKeys(Set<String> keys) {
    _retainedKeys = keys;
    for (final key in _selectedByKey.keys.toList()) {
      if (!keys.contains(key) && key != _selectedKey) {
        _selectedByKey.remove(key)?.dispose();
      }
    }
  }

  void dispose() {
    for (final notifier in _selectedByKey.values) {
      notifier.dispose();
    }
    _selectedByKey.clear();
  }
}
