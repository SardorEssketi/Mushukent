import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../network/api_error.dart';

/// Whether [error] means "the server is busy, try again later" (429 / 503 SERVICE_BUSY).
bool isBusyError(Object? error) =>
    error is MushukistanApiException && error.isBusy;

/// Delay before the automatic retry after the [attempt]-th consecutive busy answer:
/// the server's `Retry-After` when it is longer, otherwise 2, 4, 8 ... seconds, at most 60.
Duration busyRetryDelay(Object? error, int attempt) {
  final backoff = Duration(seconds: math.min(60, 2 << math.min(attempt, 5)));
  final suggested =
      error is MushukistanApiException ? error.retryAfter : null;
  if (suggested != null && suggested > backoff) {
    return suggested > const Duration(seconds: 60)
        ? const Duration(seconds: 60)
        : suggested;
  }
  return backoff;
}

/// Retry control for a failed load.
///
/// A normal error shows a [retryLabel] button. A busy error (load audit FIX-7) shows
/// "busy, retrying in N s", disables manual retry and calls [onRetry] once the countdown
/// ends, backing off further while the server stays busy, so users cannot hammer a server that
/// already asked them to wait.
class BusyRetryAction extends StatefulWidget {
  const BusyRetryAction({
    super.key,
    required this.error,
    required this.onRetry,
    required this.retryLabel,
    required this.busyLabel,
    this.filled = false,
  });

  final Object? error;
  final VoidCallback onRetry;
  final String retryLabel;
  final String Function(int seconds) busyLabel;
  final bool filled;

  @override
  State<BusyRetryAction> createState() => _BusyRetryActionState();
}

class _BusyRetryActionState extends State<BusyRetryAction> {
  Timer? _timer;
  int _remaining = 0;
  int _attempt = 0;
  Object? _scheduledFor;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(BusyRetryAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.error, widget.error)) _schedule();
  }

  void _schedule() {
    final error = widget.error;
    if (!isBusyError(error)) {
      _timer?.cancel();
      _timer = null;
      _attempt = 0;
      _remaining = 0;
      return;
    }
    if (identical(error, _scheduledFor)) return;
    _scheduledFor = error;
    _timer?.cancel();
    _remaining = busyRetryDelay(error, _attempt).inSeconds;
    _attempt++;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _remaining--);
      if (_remaining <= 0) {
        timer.cancel();
        widget.onRetry();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (isBusyError(widget.error) && _remaining > 0) {
      return Text(
        widget.busyLabel(_remaining),
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    final label = Text(widget.retryLabel);
    return widget.filled
        ? FilledButton(onPressed: widget.onRetry, child: label)
        : TextButton(onPressed: widget.onRetry, child: label);
  }
}
