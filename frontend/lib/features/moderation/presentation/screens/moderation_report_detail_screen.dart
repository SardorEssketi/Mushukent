import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/network/api_error.dart';
import '../../../../core/network/mushukistan_api.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../application/moderation_reports_controller.dart';
import '../moderation_labels.dart';
import '../widgets/moderation_badges.dart';
import 'moderation_reports_screen.dart';

final moderationReportProvider =
    FutureProvider.autoDispose.family<ReportData, String>((ref, reportId) {
  return ref.watch(mushukistanApiProvider).getReport(reportId);
});

/// The decisions a moderator can take on an open report.
enum ModerationDecision { dismiss, resolveKeep, remove }

class ModerationReportDetailScreen extends ConsumerStatefulWidget {
  const ModerationReportDetailScreen({super.key, required this.reportId});

  final String reportId;

  @override
  ConsumerState<ModerationReportDetailScreen> createState() =>
      _ModerationReportDetailScreenState();
}

class _ModerationReportDetailScreenState
    extends ConsumerState<ModerationReportDetailScreen> {
  final _noteController = TextEditingController();
  ModerationDecision? _decision;

  /// The request is in flight (controls disabled, spinner shown).
  bool _busy = false;

  /// The confirmation dialog is open; with [_busy] this makes repeated taps
  /// unable to start a second decision.
  bool _confirming = false;
  String? _error;

  /// Set when the server answered REPORT_ALREADY_HANDLED.
  bool _conflict = false;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _save(ReportData report, AppStrings strings) async {
    final decision = _decision;
    if (_busy || _confirming || decision == null || report.status != 'open') {
      return;
    }
    final removal =
        decision == ModerationDecision.remove ? removalFor(report) : null;
    if (decision == ModerationDecision.remove && removal == null) return;

    if (removal != null) {
      _confirming = true;
      final bool? confirmed;
      try {
        confirmed = await _confirm(report, removal, strings);
      } finally {
        _confirming = false;
      }
      if (!mounted || confirmed != true) return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(mushukistanApiProvider).handleReport(
            reportId: report.id,
            status: decision == ModerationDecision.dismiss
                ? 'dismissed'
                : 'resolved',
            action: removal?.action,
            note: _noteController.text,
          );
      invalidateModerationQueues(ref);
      ref.invalidate(moderationReportProvider(report.id));
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
            SnackBar(content: Text(strings.moderationDecisionSaved)));
      if (context.canPop()) context.pop();
    } on MushukistanApiException catch (error) {
      if (!mounted) return;
      if (error.code == 'REPORT_ALREADY_HANDLED') {
        // Someone else decided first: show the authoritative report instead of
        // a stale editable form, and make sure the queues drop it from Open.
        setState(() {
          _conflict = true;
          _decision = null;
        });
        invalidateModerationQueues(ref);
        ref.invalidate(moderationReportProvider(report.id));
      } else {
        setState(() => _error = _saveErrorMessage(strings, error));
      }
    } catch (_) {
      if (mounted) setState(() => _error = strings.decisionFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _saveErrorMessage(AppStrings strings, MushukistanApiException error) {
    return switch (error.kind) {
      ApiFailureKind.network => strings.decisionNetworkError,
      ApiFailureKind.forbidden ||
      ApiFailureKind.unauthorized =>
        strings.decisionForbidden,
      ApiFailureKind.notFound => strings.reportUnavailable,
      ApiFailureKind.validation => strings.decisionInvalid,
      _ => error.code == 'INVALID_PAYLOAD'
          ? strings.decisionInvalid
          : strings.decisionFailed,
    };
  }

  Future<bool?> _confirm(
    ReportData report,
    ModerationRemoval removal,
    AppStrings strings,
  ) {
    final type = reportTargetTypeLabel(strings, report.targetType);
    final title = report.target?.title?.trim();
    final subject = title == null || title.isEmpty ? type : title;
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final colors = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          icon: Icon(
            removal.isSuspension ? Icons.block : Icons.delete_outline,
            color: colors.error,
          ),
          title: Text(removal.isSuspension
              ? strings.confirmSuspendTitle
              : strings.confirmRemovalTitle(type)),
          content: Text(removal.isSuspension
              ? strings.confirmSuspendBody(subject)
              : strings.confirmRemovalBody(subject)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(strings.cancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: colors.error,
                foregroundColor: colors.onError,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(removal.isSuspension
                  ? strings.confirmSuspend
                  : strings.confirmRemove),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final reportAsync = ref.watch(moderationReportProvider(widget.reportId));
    final strings = ref.watch(appStringsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(strings.reportDetail)),
      body: reportAsync.when(
        skipLoadingOnRefresh: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) {
          final missing = error is MushukistanApiException &&
              error.kind == ApiFailureKind.notFound;
          final retryable = !missing && !isModerationAccessError(error);
          return AppStatePanel(
            icon: missing ? Icons.search_off : Icons.error_outline,
            title: strings.reportDetail,
            message: moderationLoadErrorMessage(strings, error),
            action: retryable
                ? FilledButton(
                    onPressed: () => ref
                        .invalidate(moderationReportProvider(widget.reportId)),
                    child: Text(strings.retry),
                  )
                : OutlinedButton(
                    onPressed: () => context.canPop()
                        ? context.pop()
                        : context.go('/moderation/reports'),
                    child: Text(strings.backToReports),
                  ),
          );
        },
        data: (report) => AppContentWidth(
          maxWidth: AppWidths.compact,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              if (_conflict) ...[
                _ConflictNotice(strings: strings),
                const SizedBox(height: AppSpacing.lg),
              ],
              _ReportSection(report: report, strings: strings),
              const SizedBox(height: AppSpacing.lg),
              _TargetSection(report: report, strings: strings),
              const SizedBox(height: AppSpacing.lg),
              if (report.status == 'open')
                _DecisionSection(
                  report: report,
                  strings: strings,
                  decision: _decision,
                  busy: _busy,
                  error: _error,
                  noteController: _noteController,
                  onChanged: (value) => setState(() {
                    _decision = value;
                    _error = null;
                  }),
                  onSave: () => _save(report, strings),
                )
              else
                Text(
                  strings.reportClosedNote,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConflictNotice extends StatelessWidget {
  const _ConflictNotice({required this.strings});

  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Card(
        color: colors.tertiaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.sync_problem, color: colors.onTertiaryContainer),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      strings.reportAlreadyHandledTitle,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(color: colors.onTertiaryContainer),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                strings.reportAlreadyHandledMessage,
                style: TextStyle(color: colors.onTertiaryContainer),
              ),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton(
                onPressed: () => context.canPop()
                    ? context.pop()
                    : context.go('/moderation/reports'),
                child: Text(strings.backToReports),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: MergeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            Text(value, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

class _ReportSection extends StatelessWidget {
  const _ReportSection({required this.report, required this.strings});

  final ReportData report;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(reportTargetTypeLabel(strings, report.targetType),
                    style: theme.textTheme.titleMedium),
                ReportStatusBadge(status: report.status, strings: strings),
              ],
            ),
            _InfoRow(
              label: strings.reasonLabel,
              value: report.reason?.trim().isNotEmpty == true
                  ? report.reason!.trim()
                  : strings.noReasonProvided,
            ),
            _InfoRow(
              label: strings.reportedByLabel,
              value: moderationPersonName(strings, report.reporter),
            ),
            _InfoRow(
              label: strings.submittedLabel,
              value: formatModerationTime(context, report.createdAt),
            ),
            if (report.handledAt != null) ...[
              _InfoRow(
                label: strings.handledByLabel,
                value: moderationPersonName(strings, report.handledBy),
              ),
              _InfoRow(
                label: strings.handledAtLabel,
                value: formatModerationTime(context, report.handledAt!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TargetSection extends StatelessWidget {
  const _TargetSection({required this.report, required this.strings});

  final ReportData report;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = reportTargetState(report);
    final target = report.target;
    final title = target?.title?.trim();
    final route = reportedContentRoute(report);
    final explanation = switch (state) {
      ReportTargetState.deleted => target?.deletedAt != null
          ? strings.targetDeletedExplanation(
              formatModerationTime(context, target!.deletedAt!))
          : strings.targetDeletedNoTime,
      ReportTargetState.suspended => strings.targetSuspendedExplanation,
      ReportTargetState.unavailable => strings.targetUnavailableExplanation,
      ReportTargetState.private => strings.targetPrivateExplanation,
      ReportTargetState.visible => null,
    };
    final showsContent = state == ReportTargetState.visible ||
        state == ReportTargetState.private;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(strings.reportedContentLabel,
                style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(strings.contentStateLabel,
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ReportTargetStateBadge(state: state, strings: strings),
              ],
            ),
            if (explanation != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(explanation, style: theme.textTheme.bodyMedium),
            ],
            // Removed content is not re-displayed; its state and time are enough
            // to decide, and post history keeps the moderator audit trail.
            if (showsContent && title != null && title.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Text(title, style: theme.textTheme.bodyLarge),
            ],
            if (route != null || report.targetType == 'post') ...[
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  if (route != null)
                    OutlinedButton.icon(
                      onPressed: () => context.push(route),
                      icon: const Icon(Icons.open_in_new),
                      label: Text(strings.openReportedContent),
                    ),
                  if (report.targetType == 'post' &&
                      state != ReportTargetState.unavailable)
                    TextButton.icon(
                      onPressed: () => context.push(
                          '/moderation/posts/${Uri.encodeComponent(report.targetId)}/history'),
                      icon: const Icon(Icons.history),
                      label: Text(strings.viewPostHistory),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DecisionSection extends StatelessWidget {
  const _DecisionSection({
    required this.report,
    required this.strings,
    required this.decision,
    required this.busy,
    required this.error,
    required this.noteController,
    required this.onChanged,
    required this.onSave,
  });

  final ReportData report;
  final AppStrings strings;
  final ModerationDecision? decision;
  final bool busy;
  final String? error;
  final TextEditingController noteController;
  final ValueChanged<ModerationDecision> onChanged;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final removal = removalFor(report);
    final supportsRemoval = const {
      'post',
      'lost_pet',
      'adoption_post',
      'comment',
      'user'
    }.contains(report.targetType);
    final destructive = decision == ModerationDecision.remove;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(strings.decisionTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            _DecisionOption(
              value: ModerationDecision.dismiss,
              groupValue: decision,
              enabled: !busy,
              icon: Icons.do_not_disturb_on_outlined,
              title: strings.decisionDismiss,
              subtitle: strings.decisionDismissHint,
              onSelected: onChanged,
            ),
            _DecisionOption(
              value: ModerationDecision.resolveKeep,
              groupValue: decision,
              enabled: !busy,
              icon: Icons.check_circle_outline,
              title: strings.decisionResolveKeep,
              subtitle: strings.decisionResolveKeepHint,
              onSelected: onChanged,
            ),
            if (removal != null)
              _DecisionOption(
                value: ModerationDecision.remove,
                groupValue: decision,
                enabled: !busy,
                destructive: true,
                icon: removal.isSuspension ? Icons.block : Icons.delete_outline,
                title: removal.isSuspension
                    ? strings.decisionSuspend
                    : strings.decisionRemove,
                subtitle: removal.isSuspension
                    ? strings.decisionSuspendHint
                    : report.targetType == 'comment'
                        ? strings.decisionRemoveCommentHint
                        : strings.decisionRemovePublicationHint,
                onSelected: onChanged,
              )
            else if (supportsRemoval)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Text(
                  strings.removalUnavailableHint,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: noteController,
              enabled: !busy,
              maxLines: 3,
              maxLength: 1000,
              decoration: InputDecoration(
                labelText: strings.optionalModeratorNote,
                border: const OutlineInputBorder(),
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Semantics(
                liveRegion: true,
                child: Text(error!,
                    style: TextStyle(color: theme.colorScheme.error)),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              style: destructive
                  ? FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.error,
                      foregroundColor: theme.colorScheme.onError,
                    )
                  : null,
              onPressed: busy || decision == null ? null : onSave,
              child: busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(strings.saveModerationDecision),
            ),
          ],
        ),
      ),
    );
  }
}

/// One mutually exclusive decision, with a description of its effect.
class _DecisionOption extends StatelessWidget {
  const _DecisionOption({
    required this.value,
    required this.groupValue,
    required this.enabled,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onSelected,
    this.destructive = false,
  });

  final ModerationDecision value;
  final ModerationDecision? groupValue;
  final bool enabled;
  final IconData icon;
  final String title;
  final String subtitle;
  final ValueChanged<ModerationDecision> onSelected;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final selected = value == groupValue;
    final accent = destructive ? colors.error : colors.primary;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      enabled: enabled,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        enabled: enabled,
        selected: selected,
        selectedColor: accent,
        leading: Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
          color: selected ? accent : colors.onSurfaceVariant,
        ),
        title: Row(
          children: [
            Icon(icon, size: 18, color: destructive ? colors.error : null),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(title)),
          ],
        ),
        subtitle: Text(subtitle),
        onTap: enabled ? () => onSelected(value) : null,
      ),
    );
  }
}
