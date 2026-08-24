import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    const reasonOptions = <String>[
      'Child safety / exploitation',
      'Inappropriate content',
      'Harassment or abuse',
      'Spam',
      'Other',
    ];
    final isOtherReason = _selectedReason == 'Other';

    return Scaffold(
      appBar: AppBar(title: const Text('Report content')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _targetType,
                  items: const [
                    DropdownMenuItem(value: 'post', child: Text('Post')),
                    DropdownMenuItem(value: 'comment', child: Text('Comment')),
                    DropdownMenuItem(value: 'user', child: Text('User')),
                    DropdownMenuItem(value: 'cat', child: Text('Cat')),
                    DropdownMenuItem(
                      value: 'lost_pet',
                      child: Text('Lost pet'),
                    ),
                    DropdownMenuItem(
                      value: 'adoption_post',
                      child: Text('Adoption post'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _targetType = value;
                      });
                    }
                  },
                  decoration: const InputDecoration(labelText: 'Target type'),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _targetIdController,
                  decoration: const InputDecoration(labelText: 'Target ID'),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Target ID is required.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _selectedReason,
                  items: [
                    for (final reason in reasonOptions)
                      DropdownMenuItem(value: reason, child: Text(reason)),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedReason = value;
                      if (value != 'Other') {
                        _reasonController.clear();
                      }
                    });
                  },
                  decoration: const InputDecoration(labelText: 'Reason'),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please select a reason.';
                    }
                    return null;
                  },
                ),
                if (isOtherReason) ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _reasonController,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Details',
                    ),
                    validator: (value) {
                      if (!isOtherReason) {
                        return null;
                      }
                      if (value == null || value.trim().isEmpty) {
                        return 'Please provide details.';
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
                              _message = 'Report submitted.';
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
                      : const Text('Submit report'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
