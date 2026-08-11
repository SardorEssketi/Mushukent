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
                TextFormField(
                  controller: _reasonController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Reason',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please provide a reason.';
                    }
                    return null;
                  },
                ),
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
                            await ref.read(mushukistanApiProvider).createReport(
                                  targetType: _targetType,
                                  targetId: _targetIdController.text.trim(),
                                  reason: _reasonController.text.trim(),
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
