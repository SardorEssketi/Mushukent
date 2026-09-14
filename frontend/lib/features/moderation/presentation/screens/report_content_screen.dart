import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/network/mushukistan_api.dart';

class ReportContentScreen extends ConsumerStatefulWidget {
  const ReportContentScreen({
    super.key,
    this.initialTargetType,
    this.initialTargetId,
  });

  final String? initialTargetType;
  final String? initialTargetId;

  @override
  ConsumerState<ReportContentScreen> createState() =>
      _ReportContentScreenState();
}

class _ReportContentScreenState extends ConsumerState<ReportContentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();
  final _targetIdController = TextEditingController();
  String _targetType = 'post';
  String? _selectedReason;
  bool _submitting = false;
  String? _message;
  String? _error;

  @override
  void initState() {
    super.initState();
    _targetType = widget.initialTargetType ?? 'post';
    if (widget.initialTargetId != null) {
      _targetIdController.text = widget.initialTargetId!;
    }
  }

  @override
  void dispose() {
    _reasonController.dispose();
    _targetIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final reasonOptions = <String>[
      strings.childSafetyReportReason,
      strings.inappropriateContentReportReason,
      strings.harassmentReportReason,
      strings.spamReportReason,
      strings.otherReportReason,
    ];
    final isOtherReason = _selectedReason == strings.otherReportReason;
    return Scaffold(
      appBar: AppBar(title: Text(strings.reportContent)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _targetType,
                  isExpanded: true,
                  items: [
                    DropdownMenuItem(
                      value: 'post',
                      child: Text(
                        strings.post,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'comment',
                      child: Text(
                        strings.comment,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'user',
                      child: Text(
                        strings.user,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'cat',
                      child: Text(
                        strings.cat,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'lost_pet',
                      child: Text(
                        strings.lostPet,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'adoption_post',
                      child: Text(
                        strings.adoption,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _targetType = value;
                      });
                    }
                  },
                  decoration: InputDecoration(labelText: strings.targetType),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _targetIdController,
                  decoration: InputDecoration(labelText: strings.targetIdLabel),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return strings.targetIdRequired;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _selectedReason,
                  isExpanded: true,
                  items: [
                    for (final reason in reasonOptions)
                      DropdownMenuItem(
                        value: reason,
                        child: Text(
                          reason,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedReason = value;
                      if (value != strings.otherReportReason) {
                        _reasonController.clear();
                      }
                    });
                  },
                  decoration: InputDecoration(labelText: strings.reason),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return strings.reasonRequired;
                    }
                    return null;
                  },
                ),
                if (isOtherReason) ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _reasonController,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: strings.reportDetails,
                    ),
                    validator: (value) {
                      if (!isOtherReason) {
                        return null;
                      }
                      if (value == null || value.trim().isEmpty) {
                        return strings.reasonRequired;
                      }
                      return null;
                    },
                  ),
                ],
                if (_message != null) ...[
                  const SizedBox(height: 16),
                  Text(_message!, style: const TextStyle(color: Colors.green)),
                ],
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
                  onPressed: _submitting
                      ? null
                      : () async {
                          if (!(_formKey.currentState?.validate() ?? false)) {
                            return;
                          }
                          setState(() {
                            _submitting = true;
                            _error = null;
                            _message = null;
                          });
                          try {
                            final selectedReason = _selectedReason!.trim();
                            final details = _reasonController.text.trim();
                            await ref.read(mushukistanApiProvider).createReport(
                                  targetType: _targetType,
                                  targetId: _targetIdController.text.trim(),
                                  reason:
                                      isOtherReason ? details : selectedReason,
                                );
                            setState(() {
                              _message = strings.reportSubmitted;
                            });
                          } catch (error) {
                            setState(() {
                              _error = error.toString();
                            });
                          } finally {
                            if (mounted) {
                              setState(() {
                                _submitting = false;
                              });
                            }
                          }
                        },
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(strings.submitReport),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
