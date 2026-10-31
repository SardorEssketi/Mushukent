import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Content shown before the app went to the background is revalidated after this long away.
const contentStaleAfter = Duration(minutes: 5);

/// A signed-in session is re-checked with the server after this long away.
const sessionStaleAfter = Duration(minutes: 30);

/// Monotonic time since an arbitrary start. Wall-clock changes (time zones, manual clock
/// changes, network time sync) do not affect it. Overridden with a fake clock in tests.
final monotonicClockProvider = Provider<Duration Function()>((ref) {
  final stopwatch = Stopwatch()..start();
  return () => stopwatch.elapsed;
});

/// One return to the foreground after the app was not visible.
@immutable
class AppResume {
  const AppResume({required this.sequence, required this.awayFor});

  /// Increases with every resume, so each one is a distinct event for listeners.
  final int sequence;

  /// How long the app was hidden or paused.
  final Duration awayFor;

  bool get contentIsStale => awayFor >= contentStaleAfter;
  bool get sessionIsStale => awayFor >= sessionStaleAfter;

  @override
  String toString() => 'AppResume(#$sequence, away $awayFor)';
}

/// Turns lifecycle changes into [AppResume] events.
///
/// Time away starts when the app stops being visible (hidden or paused), not when it is merely
/// inactive: a notification shade, a permission dialog or the app switcher must not count as
/// leaving. A resume without a preceding hide (or a repeated resume) emits nothing, so every
/// stay in the background produces exactly one event.
class AppResumeController extends StateNotifier<AppResume?> {
  AppResumeController(this._now) : super(null);

  final Duration Function() _now;
  Duration? _hiddenAt;
  int _sequence = 0;

  void handleLifecycle(AppLifecycleState lifecycle) {
    switch (lifecycle) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _hiddenAt ??= _now();
      case AppLifecycleState.inactive:
        break;
      case AppLifecycleState.resumed:
        final hiddenAt = _hiddenAt;
        if (hiddenAt == null) return;
        _hiddenAt = null;
        state = AppResume(sequence: ++_sequence, awayFor: _now() - hiddenAt);
    }
  }
}

final appResumeProvider =
    StateNotifierProvider<AppResumeController, AppResume?>((ref) {
  return AppResumeController(ref.watch(monotonicClockProvider));
});

/// Runs [onStale] once when the app comes back after at least [contentStaleAfter] away. Call
/// from a widget's build, like `ref.listen`; the callback runs outside the build.
void listenForStaleResume(WidgetRef ref, VoidCallback onStale) {
  ref.listen<AppResume?>(appResumeProvider, (previous, next) {
    if (next == null || next.sequence == previous?.sequence) return;
    if (next.contentIsStale) onStale();
  });
}
