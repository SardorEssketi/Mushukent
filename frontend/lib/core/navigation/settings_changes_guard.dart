import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../localization/app_strings.dart';

final settingsHasUnsavedChangesProvider = StateProvider<bool>((ref) => false);
final settingsDiscardChangesProvider =
    StateProvider<VoidCallback?>((ref) => null);

Future<bool> confirmLeavingSettings(
  BuildContext context,
  WidgetRef ref, {
  VoidCallback? onDiscard,
}) async {
  if (!ref.read(settingsHasUnsavedChangesProvider)) {
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
    (onDiscard ?? ref.read(settingsDiscardChangesProvider))?.call();
    ref.read(settingsHasUnsavedChangesProvider.notifier).state = false;
    return true;
  }
  return false;
}
