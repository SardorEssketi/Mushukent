import 'dart:async';

import 'package:flutter/widgets.dart';

/// Calls [onSeen] once, after [child] has stayed on screen long enough.
///
/// "On screen" means at least [minVisibleFraction] of the child, or of the
/// scroll viewport for a child taller than it, lies inside the nearest
/// scrollable, for [minDuration] without interruption, while its route is
/// the current one and its subtree is active (not an offstage tab). Without
/// a surrounding scrollable nothing is reported.
class SeenOnScreen extends StatefulWidget {
  const SeenOnScreen({
    super.key,
    required this.onSeen,
    required this.child,
    this.minVisibleFraction = 0.5,
    this.minDuration = const Duration(seconds: 1),
  });

  final VoidCallback onSeen;
  final Widget child;
  final double minVisibleFraction;
  final Duration minDuration;

  @override
  State<SeenOnScreen> createState() => _SeenOnScreenState();
}

class _SeenOnScreenState extends State<SeenOnScreen> {
  ScrollPosition? _position;
  Timer? _timer;
  bool _done = false;
  bool _checkScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Depend on these so returning to this route or tab re-checks visibility.
    ModalRoute.of(context);
    TickerMode.valuesOf(context);
    final position = Scrollable.maybeOf(context)?.position;
    if (!identical(position, _position)) {
      _position?.removeListener(_scheduleCheck);
      _position = _done ? null : position;
      _position?.addListener(_scheduleCheck);
    }
    _scheduleCheck();
  }

  @override
  void didUpdateWidget(SeenOnScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleCheck();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _position?.removeListener(_scheduleCheck);
    super.dispose();
  }

  void _scheduleCheck() {
    if (_done || _checkScheduled) return;
    _checkScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkScheduled = false;
      if (mounted) _check();
    });
  }

  void _check() {
    if (_done) return;
    if (_isOnScreen()) {
      _timer ??= Timer(widget.minDuration, _confirm);
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _confirm() {
    _timer = null;
    if (!mounted || _done) return;
    if (!_isOnScreen()) return;
    _done = true;
    _position?.removeListener(_scheduleCheck);
    _position = null;
    widget.onSeen();
  }

  bool _isOnScreen() {
    if (!TickerMode.valuesOf(context).enabled) return false;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return false;
    final scrollable = Scrollable.maybeOf(context);
    final box = context.findRenderObject();
    final viewportBox = scrollable?.context.findRenderObject();
    if (box is! RenderBox || viewportBox is! RenderBox) return false;
    if (!box.attached || !box.hasSize || !viewportBox.hasSize) return false;
    if (box.size.isEmpty) return false;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    final viewport = viewportBox.localToGlobal(Offset.zero) & viewportBox.size;
    final visible = rect.intersect(viewport);
    if (visible.isEmpty || visible.width <= 0 || visible.height <= 0) {
      return false;
    }
    final vertical = scrollable!.position.axis == Axis.vertical;
    final shown = vertical ? visible.height : visible.width;
    final whole = vertical ? rect.height : rect.width;
    final room = vertical ? viewport.height : viewport.width;
    final needed = widget.minVisibleFraction * (whole < room ? whole : room);
    return shown >= needed;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
