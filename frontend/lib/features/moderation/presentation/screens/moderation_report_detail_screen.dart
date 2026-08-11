import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/mushukistan_api.dart';
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
      appBar: AppBar(title: const Text('Report detail')),
      body: report == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(24),
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
                        Text(report.reason ?? 'No reason provided.'),
                        const SizedBox(height: 12),
                        Text('Target ID: ${report.targetId}'),
                        if (report.target != null) ...[
                          const SizedBox(height: 8),
                          Text('Title: ${report.target!.title ?? '-'}'),
                          Text('Status: ${report.target!.status ?? '-'}'),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                DropdownButtonFormField<String>(
                  initialValue: _selectedStatus,
                  items: const [
                    DropdownMenuItem(value: 'resolved', child: Text('Resolve')),
                    DropdownMenuItem(
                        value: 'dismissed', child: Text('Dismiss')),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedStatus = value;
                    });
                  },
                  decoration: const InputDecoration(labelText: 'Report status'),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String?>(
                  initialValue: _selectedAction,
                  items: const [
                    DropdownMenuItem<String?>(
                        value: null, child: Text('No action')),
                    DropdownMenuItem(
                        value: 'soft_delete_post',
                        child: Text('Soft delete post')),
                    DropdownMenuItem(
                      value: 'soft_delete_comment',
                      child: Text('Soft delete comment'),
                    ),
                    DropdownMenuItem(
                        value: 'suspend_user', child: Text('Suspend user')),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedAction = value;
                    });
                  },
                  decoration:
                      const InputDecoration(labelText: 'Moderation action'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _noteController,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Note'),
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
                      : const Text('Save moderation decision'),
                ),
              ],
            ),
    );
  }
}
