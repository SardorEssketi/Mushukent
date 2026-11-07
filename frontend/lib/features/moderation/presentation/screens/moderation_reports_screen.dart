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

export '../../application/moderation_reports_controller.dart'
    show moderationReportsProvider, moderationStatusFilterProvider;

class ModerationReportsScreen extends ConsumerWidget {
  const ModerationReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final status = ref.watch(moderationStatusFilterProvider);
    final reportsAsync = ref.watch(moderationReportsProvider(status));

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.moderationReports),
        actions: [
          IconButton(
            tooltip: strings.refresh,
            onPressed: () => ref.invalidate(moderationReportsProvider(status)),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: AppContentWidth(
        maxWidth: AppWidths.readable,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.sm),
              child: Semantics(
                label: strings.reportStatus,
                container: true,
                child: Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final value in moderationReportStatuses)
                      ChoiceChip(
                        label: Text(_filterLabel(strings, value)),
                        selected: value == status,
                        onSelected: (_) => ref
                            .read(moderationStatusFilterProvider.notifier)
                            .state = value,
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: reportsAsync.when(
                skipLoadingOnRefresh: false,
                data: (list) => _ReportList(
                  status: status,
                  list: list,
                  strings: strings,
                ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => AppStatePanel(
                  icon: Icons.error_outline,
                  title: strings.moderationReports,
                  message: moderationLoadErrorMessage(strings, error),
                  action: isModerationAccessError(error)
                      ? null
                      : FilledButton(
                          onPressed: () =>
                              ref.invalidate(moderationReportsProvider(status)),
                          child: Text(strings.retry),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _filterLabel(AppStrings strings, String status) => switch (status) {
      'resolved' => strings.reportFilterResolved,
      'dismissed' => strings.reportFilterDismissed,
      _ => strings.reportFilterOpen,
    };

String _emptyLabel(AppStrings strings, String status) => switch (status) {
      'resolved' => strings.noResolvedReports,
      'dismissed' => strings.noDismissedReports,
      _ => strings.noOpenReports,
    };

bool isModerationAccessError(Object error) =>
    error is MushukistanApiException &&
    (error.kind == ApiFailureKind.forbidden ||
        error.kind == ApiFailureKind.unauthorized);

/// Load errors of moderation screens, distinguishing access from connectivity.
String moderationLoadErrorMessage(AppStrings strings, Object error) {
  if (error is! MushukistanApiException) return strings.couldNotLoadReports;
  if (isModerationAccessError(error)) return strings.moderatorAccessRequired;
  return switch (error.kind) {
    ApiFailureKind.notFound => strings.reportUnavailable,
    ApiFailureKind.network => strings.reportsNetworkError,
    _ => strings.couldNotLoadReports,
  };
}

class _ReportList extends ConsumerWidget {
  const _ReportList({
    required this.status,
    required this.list,
    required this.strings,
  });

  final String status;
  final ModerationReportList list;
  final AppStrings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> refresh() =>
        ref.refresh(moderationReportsProvider(status).future);

    if (list.items.isEmpty) {
      return RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: AppSpacing.xl),
            AppStatePanel(
              icon: Icons.inbox_outlined,
              title: _emptyLabel(strings, status),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xl),
        itemCount: list.items.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
        itemBuilder: (context, index) {
          if (index == list.items.length) {
            return _ListFooter(status: status, list: list, strings: strings);
          }
          final report = list.items[index];
          return ModerationReportCard(
            report: report,
            strings: strings,
            onTap: () => context.push('/moderation/reports/${report.id}'),
          );
        },
      ),
    );
  }
}

class _ListFooter extends ConsumerWidget {
  const _ListFooter({
    required this.status,
    required this.list,
    required this.strings,
  });

  final String status;
  final ModerationReportList list;
  final AppStrings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final muted = Theme.of(context)
        .textTheme
        .bodyMedium
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    if (!list.hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Text(strings.noMoreReports,
            textAlign: TextAlign.center, style: muted),
      );
    }
    if (list.loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final controller = ref.read(moderationReportsProvider(status).notifier);
    return Column(
      children: [
        if (list.loadMoreError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              moderationLoadErrorMessage(strings, list.loadMoreError!),
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        OutlinedButton.icon(
          onPressed: controller.loadMore,
          icon: Icon(
              list.loadMoreError != null ? Icons.refresh : Icons.expand_more),
          label: Text(list.loadMoreError != null
              ? strings.retry
              : strings.loadMoreReports),
        ),
      ],
    );
  }
}

String moderationPersonName(AppStrings strings, CommentUserData? person) {
  final name = person?.name?.trim();
  return name == null || name.isEmpty ? strings.deletedAccount : name;
}

/// One queue row: what was reported, by whom and when, and the current state
/// of the report and of the reported content.
class ModerationReportCard extends StatelessWidget {
  const ModerationReportCard({
    super.key,
    required this.report,
    required this.strings,
    required this.onTap,
  });

  final ReportData report;
  final AppStrings strings;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final targetState = reportTargetState(report);

    Widget metaLine(IconData icon, String text) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: AppSpacing.xs),
            Expanded(child: Text(text, style: muted)),
          ],
        );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
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
                  Text(
                    reportTargetTypeLabel(strings, report.targetType),
                    style: theme.textTheme.titleSmall,
                  ),
                  if (report.status != 'open')
                    ReportStatusBadge(status: report.status, strings: strings),
                  if (targetState != ReportTargetState.visible)
                    ReportTargetStateBadge(
                        state: targetState, strings: strings),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                report.reason?.trim().isNotEmpty == true
                    ? report.reason!.trim()
                    : strings.noReasonProvided,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              metaLine(
                Icons.person_outline,
                strings.reportedByLine(
                  moderationPersonName(strings, report.reporter),
                  formatModerationTime(context, report.createdAt),
                ),
              ),
              if (report.handledAt != null) ...[
                const SizedBox(height: AppSpacing.xs),
                metaLine(
                  Icons.gavel_outlined,
                  strings.handledByLine(
                    moderationPersonName(strings, report.handledBy),
                    formatModerationTime(context, report.handledAt!),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
