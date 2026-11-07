import 'package:flutter/material.dart';

import '../localization/app_strings.dart';

/// Eye button of a password field. Its tooltip, which is also its accessible
/// name, says what pressing it does: "Show password" while the text is masked,
/// "Hide password" while it is visible. The password itself is never exposed.
class PasswordVisibilityButton extends StatelessWidget {
  const PasswordVisibilityButton({
    super.key,
    required this.obscured,
    required this.onPressed,
    required this.strings,
  });

  final bool obscured;
  final VoidCallback? onPressed;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: obscured ? strings.showPassword : strings.hidePassword,
      onPressed: onPressed,
      icon: Icon(
        obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
      ),
    );
  }
}

/// The small X on a selected photo of a publication draft. Each button is
/// named by the photo's position ("Remove photo 2 of 3"), so assistive
/// technology can tell several of them apart.
class PhotoRemoveButton extends StatelessWidget {
  const PhotoRemoveButton({
    super.key,
    required this.position,
    required this.total,
    required this.onPressed,
    required this.strings,
  });

  /// One-based position of the photo in the draft.
  final int position;
  final int total;
  final VoidCallback? onPressed;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      tooltip: strings.removePhotoNumber(position, total),
      onPressed: onPressed,
      icon: const Icon(Icons.close, size: 16),
    );
  }
}
