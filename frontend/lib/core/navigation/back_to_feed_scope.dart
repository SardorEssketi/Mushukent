import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Android Back on a sign-in or session page that a redirect left as the only page.
///
/// A guest who opens Add or Profile is redirected to "Account required"; the redirect replaces
/// the app shell, so nothing is left to go back to and Android would close the app. Here Back
/// opens the Feed instead, like the page's "Continue browsing" action, through the router (its
/// redirects still apply, so nothing protected opens). When a real page is underneath (the
/// Feed's Login button pushes the sign-in page), Back pops to it as usual.
///
/// Browsers handle Back through their history, so web is left alone.
class BackToFeedScope extends StatelessWidget {
  const BackToFeedScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return child;
    final hasPageBelow = ModalRoute.of(context)?.canPop ?? true;
    return PopScope<Object?>(
      canPop: hasPageBelow,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) context.go('/feed');
      },
      child: child,
    );
  }
}
