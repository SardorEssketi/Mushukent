import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../localization/app_strings.dart';

final settingsHasUnsavedChangesProvider = StateProvider<bool>((ref) => false);
final settingsDiscardChangesProvider =
    StateProvider<VoidCallback?>((ref) => null);
final editProfileHasUnsavedChangesProvider =
    StateProvider<bool>((ref) => false);

Future<bool> confirmLeavingSettings(
  BuildContext context,
  WidgetRef ref, {
  VoidCallback? onDiscard,
}) async {
  final settingsHaveChanges = ref.read(settingsHasUnsavedChangesProvider);
  final editProfileHasChanges = ref.read(editProfileHasUnsavedChangesProvider);
  if (!settingsHaveChanges && !editProfileHasChanges) {
    return true;
  }

  final strings = ref.read(appStringsProvider);
  final shouldDiscard = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(strings.unsavedChangesTitle),
      content: Text(strings.unsavedChangesMessage),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(strings.keepEditing),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(strings.discardChanges),
        ),
      ],
    ),
  );

  if (shouldDiscard == true) {
    if (settingsHaveChanges) {
      (onDiscard ?? ref.read(settingsDiscardChangesProvider))?.call();
    }
    ref.read(settingsHasUnsavedChangesProvider.notifier).state = false;
    ref.read(editProfileHasUnsavedChangesProvider.notifier).state = false;
    return true;
  }
  return false;
}
