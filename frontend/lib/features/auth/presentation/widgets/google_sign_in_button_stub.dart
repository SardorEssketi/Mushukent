import 'package:flutter/widgets.dart';

class GoogleSignInEntryButton extends StatelessWidget {
  const GoogleSignInEntryButton({
    super.key,
    required this.enabled,
    this.acceptTerms = false,
    this.acceptPrivacy = false,
    this.onIdToken,
    this.onError,
  });

  final bool enabled;
  final bool acceptTerms;
  final bool acceptPrivacy;
  final Future<void> Function(String idToken)? onIdToken;
  final void Function(String message)? onError;

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
