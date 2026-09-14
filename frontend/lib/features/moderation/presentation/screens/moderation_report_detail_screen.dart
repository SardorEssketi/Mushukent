import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/network/mushukistan_api.dart';
import '../../../../core/widgets/app_surface.dart';
import 'moderation_reports_screen.dart';

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
    final reportsAsync = ref.watch(moderationReportsProvider);
    final strings = ref.watch(appStringsProvider);
    final report = reportsAsync.maybeWhen(
      data: (page) {
        for (final item in page.items) {
          if (item.id == widget.reportId) {
            return item;
          }
        }
        return null;
      },
      orElse: () => null,
    );

    return Scaffold(
      appBar: AppBar(title: Text(strings.reportDetail)),
      body: report == null
          ? reportsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => AppStatePanel(
                icon: Icons.error_outline,
                title: strings.reportDetail,
                message: strings.couldNotLoadReports,
                action: FilledButton(
                  onPressed: () => ref.invalidate(moderationReportsProvider),
                  child: Text(strings.retry),
                ),
              ),
              data: (_) => AppStatePanel(
                icon: Icons.report_outlined,
                title: strings.reportDetail,
                message: strings.reportUnavailable,
                action: FilledButton(
                  onPressed: context.pop,
                  child: Text(strings.backToReports),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${report.targetType} | ${report.status}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(report.reason ?? strings.noReasonProvided),
                        if (report.target != null) ...[
                          const SizedBox(height: 8),
                          Text(
                              strings.targetTitle(report.target!.title ?? '-')),
                          Text(strings
                              .targetStatus(report.target!.status ?? '-')),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                DropdownButtonFormField<String>(
                  initialValue: _selectedStatus,
                  isExpanded: true,
                  items: [
                    DropdownMenuItem(
                        value: 'resolved', child: Text(strings.resolve)),
                    DropdownMenuItem(
                        value: 'dismissed', child: Text(strings.dismiss)),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedStatus = value;
                    });
                  },
                  decoration: InputDecoration(labelText: strings.reportStatus),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String?>(
                  initialValue: _selectedAction,
                  isExpanded: true,
                  items: [
                    DropdownMenuItem<String?>(
                        value: null, child: Text(strings.noAction)),
                    DropdownMenuItem(
                        value: 'soft_delete_post',
                        child: Text(strings.softDeletePost)),
                    DropdownMenuItem(
                      value: 'soft_delete_comment',
                      child: Text(strings.softDeleteComment),
                    ),
                    DropdownMenuItem(
                        value: 'suspend_user',
                        child: Text(strings.suspendUser)),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedAction = value;
                    });
                  },
                  decoration:
                      InputDecoration(labelText: strings.moderationAction),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _noteController,
                  maxLines: 3,
                  decoration: InputDecoration(labelText: strings.note),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                const SizedBox(height: 24),
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
                          } catch (error) {
                            setState(() {
                              _error = error.toString();
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
    );
  }
}
