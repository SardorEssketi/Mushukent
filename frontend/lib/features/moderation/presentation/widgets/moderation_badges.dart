import 'package:flutter/material.dart';

import '../../../../core/localization/app_strings.dart';
import '../moderation_labels.dart';

/// A compact, labelled status pill. Colour is never the only signal: every
/// badge carries an icon and text.
class ModerationBadge extends StatelessWidget {
  const ModerationBadge({
    super.key,
    required this.label,
    required this.icon,
    required this.background,
    required this.foreground,
  });

  final String label;
  final IconData icon;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: foreground),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}

class ReportStatusBadge extends StatelessWidget {
  const ReportStatusBadge({
    super.key,
    required this.status,
    required this.strings,
  });

  final String status;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (icon, background, foreground) = switch (status) {
      'open' => (
          Icons.flag_outlined,
          colors.tertiaryContainer,
          colors.onTertiaryContainer
        ),
      'resolved' => (
          Icons.check_circle_outline,
          colors.primaryContainer,
          colors.onPrimaryContainer
        ),
      _ => (
          Icons.do_not_disturb_on_outlined,
          colors.surfaceContainerHighest,
          colors.onSurfaceVariant
        ),
    };
    return ModerationBadge(
      label: reportStatusLabel(strings, status),
      icon: icon,
      background: background,
      foreground: foreground,
    );
  }
}

class ReportTargetStateBadge extends StatelessWidget {
  const ReportTargetStateBadge({
    super.key,
    required this.state,
    required this.strings,
  });

  final ReportTargetState state;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (icon, background, foreground) = switch (state) {
      ReportTargetState.visible => (
          Icons.visibility_outlined,
          colors.secondaryContainer,
          colors.onSecondaryContainer
        ),
      ReportTargetState.private => (
          Icons.lock_outline,
          colors.secondaryContainer,
          colors.onSecondaryContainer
        ),
      ReportTargetState.deleted => (
          Icons.delete_outline,
          colors.errorContainer,
          colors.onErrorContainer
        ),
      ReportTargetState.suspended => (
          Icons.block,
          colors.errorContainer,
          colors.onErrorContainer
        ),
      ReportTargetState.unavailable => (
          Icons.help_outline,
          colors.surfaceContainerHighest,
          colors.onSurfaceVariant
        ),
    };
    return ModerationBadge(
      label: reportTargetStateLabel(strings, state),
      icon: icon,
      background: background,
      foreground: foreground,
    );
  }
}
