import 'package:flutter/widgets.dart';

class GoogleSignInEntryButton extends StatelessWidget {
  const GoogleSignInEntryButton({
    super.key,
    required this.enabled,
    this.acceptTerms = false,
    this.acceptPrivacy = false,
  });

  final bool enabled;
  final bool acceptTerms;
  final bool acceptPrivacy;

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
