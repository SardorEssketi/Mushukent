import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/network/mushukistan_api.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/widgets/app_surface.dart';
import 'moderation_reports_screen.dart';

final moderationReportProvider =
    FutureProvider.autoDispose.family<ReportData, String>((ref, reportId) {
  return ref.watch(mushukistanApiProvider).getReport(reportId);
});

class ModerationReportDetailScreen extends ConsumerStatefulWidget {
  const ModerationReportDetailScreen({super.key, required this.reportId});

  final String reportId;

  @override
  ConsumerState<ModerationReportDetailScreen> createState() =>
      _ModerationReportDetailScreenState();
}

class _ModerationReportDetailScreenState
    extends ConsumerState<ModerationReportDetailScreen> {
  String? _selectedStatus = 'resolved';
  String? _selectedAction;
  final _noteController = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reportAsync = ref.watch(moderationReportProvider(widget.reportId));
    final strings = ref.watch(appStringsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(strings.reportDetail)),
      body: reportAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => AppStatePanel(
          icon: Icons.error_outline,
          title: strings.reportDetail,
          message: strings.couldNotLoadReports,
          action: FilledButton(
            onPressed: () => ref.invalidate(
              moderationReportProvider(widget.reportId),
            ),
            child: Text(strings.retry),
          ),
        ),
        data: (report) => AppContentWidth(
          maxWidth: AppWidths.compact,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${report.targetType} | ${report.status}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(report.reason ?? strings.noReasonProvided),
                      if (report.target != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Text(strings.targetTitle(report.target!.title ?? '-')),
                        Text(
                            strings.targetStatus(report.target!.status ?? '-')),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              DropdownButtonFormField<String>(
                initialValue: _selectedStatus,
                isExpanded: true,
                items: [
                  DropdownMenuItem(
                    value: 'resolved',
                    child: Text(strings.resolve),
                  ),
                  DropdownMenuItem(
                    value: 'dismissed',
                    child: Text(strings.dismiss),
                  ),
                ],
                onChanged: (value) {
                  setState(() {
                    _selectedStatus = value;
                  });
                },
                decoration: InputDecoration(labelText: strings.reportStatus),
              ),
              const SizedBox(height: AppSpacing.lg),
              DropdownButtonFormField<String?>(
                initialValue: _selectedAction,
                isExpanded: true,
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text(strings.noAction),
                  ),
                  DropdownMenuItem(
                    value: 'soft_delete_post',
                    child: Text(strings.softDeletePost),
                  ),
                  DropdownMenuItem(
                    value: 'soft_delete_comment',
                    child: Text(strings.softDeleteComment),
                  ),
                  DropdownMenuItem(
                    value: 'suspend_user',
                    child: Text(strings.suspendUser),
                  ),
                ],
                onChanged: (value) {
                  setState(() {
                    _selectedAction = value;
                  });
                },
                decoration: InputDecoration(
                  labelText: strings.moderationAction,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: _noteController,
                maxLines: 3,
                decoration: InputDecoration(labelText: strings.note),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.lg),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              FilledButton(
                onPressed: _saving
                    ? null
                    : () async {
                        if (_selectedStatus == null) {
                          return;
                        }
                        setState(() {
                          _saving = true;
                          _error = null;
                        });
                        try {
                          await ref.read(mushukistanApiProvider).handleReport(
                                reportId: widget.reportId,
                                status: _selectedStatus!,
                                action: _selectedAction,
                                note: _noteController.text,
                              );
                          ref.invalidate(moderationReportsProvider);
                          if (context.mounted) {
                            context.pop();
                          }
                        } catch (_) {
                          setState(() {
                            _error = strings.couldNotLoadReports;
                          });
                        } finally {
                          if (mounted) {
                            setState(() {
                              _saving = false;
                            });
                          }
                        }
                      },
                child: _saving
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
      ),
    );
  }
}
