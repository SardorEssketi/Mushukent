import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/network/api_error.dart';
import '../../../../core/network/mushukistan_api.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/widgets/app_surface.dart';

class ReportContentScreen extends ConsumerStatefulWidget {
  const ReportContentScreen({
    super.key,
    this.initialTargetType,
    this.initialTargetId,
    this.initialTargetLabel,
  });

  final String? initialTargetType;
  final String? initialTargetId;
  final String? initialTargetLabel;

  @override
  ConsumerState<ReportContentScreen> createState() =>
      _ReportContentScreenState();
}

class _ReportContentScreenState extends ConsumerState<ReportContentScreen> {
  static const _supportedTargetTypes = <String>{
    'post',
    'comment',
    'user',
    'cat',
    'lost_pet',
    'adoption_post',
  };

  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();
  String? _selectedReason;
  bool _submitting = false;
  bool _submitted = false;
  String? _error;

  bool get _hasValidTarget {
    final targetType = widget.initialTargetType;
    final targetId = widget.initialTargetId?.trim();
    return targetType != null &&
        _supportedTargetTypes.contains(targetType) &&
        targetId != null &&
        targetId.isNotEmpty;
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final targetType = widget.initialTargetType;
    final reasonOptions = <String>[
      strings.childSafetyReportReason,
      strings.inappropriateContentReportReason,
      strings.harassmentReportReason,
      strings.spamReportReason,
      strings.otherReportReason,
    ];
    final isOtherReason = _selectedReason == strings.otherReportReason;

    if (!_hasValidTarget || targetType == null) {
      return Scaffold(
        appBar: AppBar(title: Text(strings.reportContent)),
        body: AppStatePanel(
          icon: Icons.report_outlined,
          title: strings.reportContent,
          message: strings.reportTargetUnavailable,
          action: FilledButton(
            onPressed: () => context.go('/feed'),
            child: Text(strings.feed),
          ),
        ),
      );
    }

    if (_submitted) {
      return Scaffold(
        appBar: AppBar(title: Text(strings.reportContent)),
        body: AppStatePanel(
          icon: Icons.check_circle_outline,
          title: strings.reportSubmitted,
          action: FilledButton(
            onPressed: () =>
                context.canPop() ? context.pop() : context.go('/feed'),
            child: Text(strings.feed),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(strings.reportContent)),
      body: AppContentWidth(
        maxWidth: AppWidths.compact,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(_targetIcon(targetType)),
                title: Text(_targetLabel(targetType, strings)),
                subtitle: Text(
                  widget.initialTargetLabel?.trim().isNotEmpty == true
                      ? widget.initialTargetLabel!.trim()
                      : strings.reportTargetSummary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Divider(),
              const SizedBox(height: AppSpacing.sm),
              Text(
                strings.reason,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              RadioGroup<String>(
                groupValue: _selectedReason,
                onChanged: (value) {
                  if (_submitting) {
                    return;
                  }
                  setState(() {
                    _selectedReason = value;
                    if (value != strings.otherReportReason) {
                      _reasonController.clear();
                    }
                  });
                },
                child: Column(
                  children: [
                    for (final reason in reasonOptions)
                      RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        value: reason,
                        title: Text(reason),
                      ),
                  ],
                ),
              ),
              if (isOtherReason) ...[
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _reasonController,
                  maxLines: 4,
                  decoration: InputDecoration(labelText: strings.reportDetails),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? strings.reasonRequired
                      : null,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              FilledButton(
                onPressed: _submitting ? null : _submit,
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
    );
  }

  Future<void> _submit() async {
    final strings = ref.read(appStringsProvider);
    if (_selectedReason == null) {
      setState(() => _error = strings.reasonRequired);
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final selectedReason = _selectedReason!;
      await ref.read(mushukistanApiProvider).createReport(
            targetType: widget.initialTargetType!,
            targetId: widget.initialTargetId!.trim(),
            reason: selectedReason == strings.otherReportReason
                ? _reasonController.text.trim()
                : selectedReason,
          );
      if (mounted) {
        setState(() => _submitted = true);
      }
    } on MushukistanApiException catch (error) {
      if (mounted) {
        setState(() => _error = error.userMessage);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = strings.couldNotSubmitReport);
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }
}

IconData _targetIcon(String type) => switch (type) {
      'comment' => Icons.comment_outlined,
      'user' => Icons.person_outline,
      'cat' => Icons.pets_outlined,
      'lost_pet' => Icons.search_outlined,
      'adoption_post' => Icons.home_outlined,
      _ => Icons.article_outlined,
    };

String _targetLabel(String type, AppStrings strings) => switch (type) {
      'comment' => strings.comment,
      'user' => strings.user,
      'cat' => strings.cat,
      'lost_pet' => strings.lostPet,
      'adoption_post' => strings.adoption,
      _ => strings.post,
    };
