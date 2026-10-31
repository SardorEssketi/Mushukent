import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../localization/app_strings.dart';

/// Android Back at the top level of the app shell. Pages opened inside a tab are popped by that
/// tab's own navigator before this is consulted, so it only sees Back on a tab's root page:
///
/// * Map, Add, Leaderboard or Profile: Back opens the Feed (through [onBackToFeed], which keeps
///   the unsaved-changes guard of a normal tab switch).
/// * Feed: the first Back shows a hint; another Back within [exitWindow] is left to the system,
///   which closes the app the usual way. Leaving the Feed screen cancels the pending exit.
///
/// `canPop` is declarative, so Android's predictive Back knows beforehand whether Back stays in
/// the app or leaves it. Browsers handle Back through their history, so web is left alone.
class ShellBackHandler extends ConsumerStatefulWidget {
  const ShellBackHandler({
    super.key,
    required this.navigationShell,
    required this.location,
    required this.onBackToFeed,
    required this.child,
    this.exitWindow = const Duration(seconds: 2),
  });

  final StatefulNavigationShell navigationShell;
  final String location;
  final VoidCallback onBackToFeed;
  final Widget child;
  final Duration exitWindow;

  static const feedBranchIndex = 0;

  @override
  ConsumerState<ShellBackHandler> createState() => _ShellBackHandlerState();
}

class _ShellBackHandlerState extends ConsumerState<ShellBackHandler> {
  Timer? _exitTimer;

  bool get _onFeed =>
      widget.navigationShell.currentIndex == ShellBackHandler.feedBranchIndex;

  bool get _exitArmed => _exitTimer != null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Another screen opened on top of the shell (a post, a profile...): start over.
    if (ModalRoute.of(context)?.isCurrent == false) _disarm();
  }

  @override
  void didUpdateWidget(ShellBackHandler oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location != widget.location ||
        oldWidget.navigationShell.currentIndex !=
            widget.navigationShell.currentIndex) {
      _disarm();
    }
  }

  @override
  void dispose() {
    _exitTimer?.cancel();
    if (_hint != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _hideHint());
    }
    super.dispose();
  }

  /// Only called from didUpdateWidget/didChangeDependencies, which are always followed by a
  /// build, so the new `canPop` takes effect without a setState.
  void _disarm() {
    if (!_exitArmed) return;
    _exitTimer?.cancel();
    _exitTimer = null;
    // The messenger cannot change while the tree is being built: hide the hint after the frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => _hideHint());
  }

  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _hint;
  ScaffoldMessengerState? _hintMessenger;

  /// Hides the hint if it is still on screen. Snackbars queue, so while it is visible it is the
  /// current one and nothing else is hidden by mistake.
  void _hideHint() {
    if (_hint == null) return;
    _hint = null;
    final messenger = _hintMessenger;
    if (messenger != null && messenger.mounted) messenger.hideCurrentSnackBar();
  }

  void _armExit() {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger != null) {
      messenger.hideCurrentSnackBar();
      final hint = messenger.showSnackBar(SnackBar(
        content: Text(ref.read(appStringsProvider).pressBackAgainToExit),
        // The exit window closes it. The snackbar's own timer starts late (after its entrance
        // animation) and would outlast the window; it only remains as a fallback.
        duration: widget.exitWindow + const Duration(seconds: 1),
      ));
      _hint = hint;
      _hintMessenger = messenger;
      hint.closed.then((_) {
        if (identical(_hint, hint)) _hint = null;
      });
    }
    setState(() {
      _exitTimer = Timer(widget.exitWindow, () {
        _hideHint();
        if (mounted) setState(() => _exitTimer = null);
      });
    });
  }

  void _handleBack(bool didPop, Object? result) {
    if (didPop) return;
    if (!_onFeed) {
      widget.onBackToFeed();
      return;
    }
    _armExit();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return widget.child;
    final canPop = _onFeed && _exitArmed;
    return PopScope<Object?>(
      canPop: canPop,
      onPopInvokedWithResult: _handleBack,
      // The tabs' own navigators report "cannot handle Back" whenever they are at their root,
      // and that report would reach Android after this PopScope's. Like a Navigator does for its
      // nested navigators, correct it while this handler still takes Back, so predictive Back
      // only plays the leave-the-app animation when Back really leaves the app.
      child: NotificationListener<NavigationNotification>(
        onNotification: (notification) {
          if (notification.canHandlePop || canPop) return false;
          const NavigationNotification(canHandlePop: true).dispatch(context);
          return true;
        },
        child: widget.child,
      ),
    );
  }
}
