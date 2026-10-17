import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/localization/feedback_strings.dart';
import '../../../../core/network/api_error.dart';
import '../../../../core/network/mushukistan_api.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/widgets/app_surface.dart';

const feedbackMinLength = 10;
const feedbackMaxLength = 2000;

/// Optional build-time app version (`--dart-define=MUSHUKISTAN_APP_VERSION`).
/// Omitted from the submission when not provided.
const _appVersion = String.fromEnvironment('MUSHUKISTAN_APP_VERSION');

enum FeedbackCategory {
  bug('bug', Icons.bug_report_outlined),
  suggestion('suggestion', Icons.lightbulb_outline),
  other('other', Icons.chat_bubble_outline);

  const FeedbackCategory(this.apiValue, this.icon);

  final String apiValue;
  final IconData icon;
}

class FeedbackScreen extends ConsumerStatefulWidget {
  const FeedbackScreen({super.key});

  @override
  ConsumerState<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends ConsumerState<FeedbackScreen> {
  final _formKey = GlobalKey<FormState>();
  final _messageController = TextEditingController();
  FeedbackCategory? _category;
  bool _categoryMissing = false;
  bool _submitting = false;
  bool _submitted = false;
  bool _exitApproved = false;
  String? _error;

  bool get _hasDraft => _messageController.text.trim().isNotEmpty;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(feedbackStringsProvider);
    final appStrings = ref.watch(appStringsProvider);
    final mobile = MediaQuery.sizeOf(context).width < AppWidths.compact;

    return PopScope<void>(
      canPop: _exitApproved || _submitted || (!_hasDraft && !_submitting),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_requestExit(appStrings));
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
        appBar: AppBar(
          title: Text(strings.entryTitle),
          leading: BackButton(onPressed: () => _requestExit(appStrings)),
        ),
        body: AppContentWidth(
          maxWidth: AppWidths.readable,
          child: _submitted
              ? AppStatePanel(
                  icon: Icons.favorite_outline_rounded,
                  title: strings.thanks,
                  action: FilledButton(
                    onPressed: _leave,
                    child: Text(strings.backToProfile),
                  ),
                )
              : _buildForm(context, strings, mobile),
        ),
      ),
    );
  }

  Widget _buildForm(
      BuildContext context, FeedbackStrings strings, bool mobile) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Form(
      key: _formKey,
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.all(mobile ? AppSpacing.lg : AppSpacing.xl),
        children: [
          Semantics(
            header: true,
            child: Text(
              strings.heading,
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            strings.description,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(strings.categoryLabel, style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final category in FeedbackCategory.values)
                ChoiceChip(
                  key: ValueKey('feedback-category-${category.apiValue}'),
                  avatar: Icon(category.icon, size: 18),
                  label: Text(_categoryLabel(category, strings)),
                  selected: _category == category,
                  onSelected: _submitting
                      ? null
                      : (_) => setState(() {
                            _category = category;
                            _categoryMissing = false;
                          }),
                ),
            ],
          ),
          if (_categoryMissing)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                strings.categoryRequired,
                style: theme.textTheme.bodySmall?.copyWith(color: colors.error),
              ),
            ),
          const SizedBox(height: AppSpacing.xl),
          TextFormField(
            key: const ValueKey('feedback-message'),
            controller: _messageController,
            enabled: !_submitting,
            minLines: 5,
            maxLines: 10,
            maxLength: feedbackMaxLength,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.newline,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: strings.messageLabel,
              hintText: strings.messageHint,
              alignLabelWithHint: true,
            ),
            validator: (value) {
              final text = value?.trim() ?? '';
              if (text.isEmpty) return strings.messageRequired;
              if (text.length < feedbackMinLength) {
                return strings.messageTooShort;
              }
              return null;
            },
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.md),
            Semantics(
              liveRegion: true,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.errorContainer,
                  borderRadius: BorderRadius.circular(AppRadii.md),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.error_outline,
                          size: 20, color: colors.onErrorContainer),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          _error!,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: colors.onErrorContainer),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          FilledButton(
            key: const ValueKey('feedback-send'),
            onPressed: _submitting ? null : () => _submit(strings),
            child: _submitting
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(strings.sending),
                    ],
                  )
                : Text(strings.send),
          ),
        ],
      ),
    );
  }

  String _categoryLabel(FeedbackCategory category, FeedbackStrings strings) =>
      switch (category) {
        FeedbackCategory.bug => strings.bug,
        FeedbackCategory.suggestion => strings.suggestion,
        FeedbackCategory.other => strings.other,
      };

  Future<void> _submit(FeedbackStrings strings) async {
    if (_submitting) return;
    final formValid = _formKey.currentState?.validate() ?? false;
    final category = _category;
    if (category == null) setState(() => _categoryMissing = true);
    if (!formValid || category == null) return;

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(mushukistanApiProvider).submitFeedback(
            category: category.apiValue,
            message: _messageController.text.trim(),
            platform: kIsWeb ? 'web' : 'android',
            appVersion: _appVersion,
          );
      if (mounted) setState(() => _submitted = true);
    } on MushukistanApiException catch (error) {
      if (mounted) setState(() => _error = _messageFor(error, strings));
    } catch (_) {
      if (mounted) setState(() => _error = strings.genericError);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _messageFor(MushukistanApiException error, FeedbackStrings strings) {
    if (error.code == 'FEEDBACK_RATE_LIMITED') return strings.rateLimited;
    return switch (error.kind) {
      ApiFailureKind.network => strings.networkError,
      ApiFailureKind.unauthorized => strings.sessionExpired,
      _ => strings.genericError,
    };
  }

  void _leave() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/profile');
    }
  }

  Future<void> _requestExit(AppStrings appStrings) async {
    if (_submitted || !_hasDraft) {
      _leave();
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(appStrings.unsavedChangesTitle),
        content: Text(appStrings.unsavedChangesMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(appStrings.keepEditing),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(appStrings.discardChanges),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      setState(() => _exitApproved = true);
      // PopScope must rebuild with canPop == true before the route is popped.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _leave();
      });
    }
  }
}
