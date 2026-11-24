import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/navigation/settings_changes_guard.dart';
import '../../../../core/network/api_error.dart';
import '../../../../core/network/mushukistan_api.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/validation/phone_numbers.dart';
import '../../../../core/widgets/app_surface.dart';
import 'profile_screen.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _telegramController = TextEditingController();
  final _bioController = TextEditingController();
  bool _initialised = false;
  bool _saving = false;
  String? _error;
  String _initialName = '';
  String _initialPhone = '';
  String _initialTelegram = '';
  String _initialBio = '';
  bool _exitApproved = false;
  bool _confirmingExit = false;

  @override
  void initState() {
    super.initState();
    ref.read(editProfileHasUnsavedChangesProvider.notifier).state = false;
    for (final controller in [
      _nameController,
      _phoneController,
      _telegramController,
      _bioController,
    ]) {
      controller.addListener(_onInputChanged);
    }
  }

  bool get _hasChanges =>
      _initialised &&
      (_nameController.text != _initialName ||
          _phoneController.text != _initialPhone ||
          _telegramController.text != _initialTelegram ||
          _bioController.text != _initialBio);

  void _onInputChanged() {
    if (!_initialised) return;
    _syncUnsavedChanges();
    if (mounted) setState(() {});
  }

  void _syncUnsavedChanges() {
    final dirty = _hasChanges;
    if (ref.read(editProfileHasUnsavedChangesProvider) != dirty) {
      ref.read(editProfileHasUnsavedChangesProvider.notifier).state = dirty;
    }
  }

  Future<void> _requestExit() async {
    if (_saving || _confirmingExit || !mounted) return;
    if (_hasChanges && !_exitApproved) {
      _confirmingExit = true;
      final strings = ref.read(appStringsProvider);
      final discard = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(strings.unsavedChangesTitle),
          content: Text(strings.unsavedChangesMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(strings.keepEditing),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(strings.discardChanges),
            ),
          ],
        ),
      );
      _confirmingExit = false;
      if (discard != true || !mounted) return;
    }
    ref.read(editProfileHasUnsavedChangesProvider.notifier).state = false;
    setState(() => _exitApproved = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.pop();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _telegramController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(profileMeProvider);
    final strings = ref.watch(appStringsProvider);
    if (!_initialised && profileAsync.hasValue) {
      final profile = profileAsync.value!;
      _nameController.text = profile.name ?? '';
      _phoneController.text = profile.phoneNumber ?? '';
      _telegramController.text = profile.telegramUsername ?? '';
      _bioController.text = profile.bio ?? '';
      _initialName = _nameController.text;
      _initialPhone = _phoneController.text;
      _initialTelegram = _telegramController.text;
      _initialBio = _bioController.text;
      _initialised = true;
      _syncUnsavedChanges();
    }

    final mobile = MediaQuery.sizeOf(context).width < AppWidths.compact;
    final content = PopScope<void>(
      canPop: _exitApproved || (!_hasChanges && !_saving),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_requestExit());
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
        appBar: AppBar(
          title: Text(strings.editProfile),
          leading: BackButton(onPressed: _requestExit),
        ),
        body: profileAsync.when(
          data: (profile) => Form(
            key: _formKey,
            child: AppContentWidth(
              maxWidth: AppWidths.readable,
              child: ListView(
                padding: EdgeInsets.all(mobile ? AppSpacing.lg : AppSpacing.xl),
                children: [
                  Text(strings.personalInformation,
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.lg),
                  TextFormField(
                    controller: _nameController,
                    decoration:
                        InputDecoration(labelText: strings.nameOptional),
                    maxLength: 100,
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _phoneController,
                    decoration: InputDecoration(
                      labelText: strings.phoneNumber,
                      hintText: uzbekPhoneFormat,
                      // The format is needed to type a valid number, so it
                      // wraps at any text size. helperText is ellipsized to
                      // one line by default; a helper widget has no limit.
                      helper: Text(
                        strings.uzbekPhoneFormatHelp,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                      errorMaxLines: 12,
                    ),
                    keyboardType: TextInputType.phone,
                    maxLength: 32,
                    validator: (value) {
                      final phone = value?.trim() ?? '';
                      if (phone.isEmpty) return null;
                      return isValidUzbekPhoneNumber(phone)
                          ? null
                          : strings.invalidUzbekPhone;
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _telegramController,
                    decoration: InputDecoration(
                      labelText: strings.telegramUsername,
                      prefixText: '@',
                    ),
                    maxLength: 32,
                    validator: (value) {
                      final username =
                          value?.trim().replaceFirst('@', '') ?? '';
                      if (username.isEmpty) return null;
                      return RegExp(r'^[A-Za-z0-9_]{5,32}$').hasMatch(username)
                          ? null
                          : strings.telegramValidation;
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _bioController,
                    decoration: InputDecoration(
                      labelText: strings.bio,
                    ),
                    minLines: 3,
                    maxLines: 5,
                    maxLength: 1000,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  if (mobile) ...[
                    FilledButton(
                      onPressed: _saving || !_hasChanges ? null : _saveProfile,
                      child: _saveLabel(strings),
                    ),
                    TextButton(
                      onPressed: _saving ? null : _requestExit,
                      child: Text(strings.cancel),
                    ),
                  ] else
                    Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                      TextButton(
                        onPressed: _saving ? null : _requestExit,
                        child: Text(strings.cancel),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      FilledButton(
                        onPressed:
                            _saving || !_hasChanges ? null : _saveProfile,
                        child: _saveLabel(strings),
                      ),
                    ]),
                  const SizedBox(height: AppSpacing.xl),
                ],
              ),
            ),
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => _ErrorPanel(
            message: strings.couldNotLoadProfile,
            onRetry: () => ref.invalidate(profileMeProvider),
            retryLabel: strings.retry,
          ),
        ),
      ),
    );
    if (Router.maybeOf(context) == null) return content;
    return BackButtonListener(
      onBackButtonPressed: () async {
        if (ModalRoute.of(context)?.isCurrent != true) return false;
        await _requestExit();
        return true;
      },
      child: content,
    );
  }

  Widget _saveLabel(AppStrings strings) => _saving
      ? const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
      : Text(strings.saveChanges);

  Future<void> _saveProfile() async {
    if (_saving || !_hasChanges) {
      return;
    }
    if (!(_formKey.currentState?.validate() ?? true)) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final api = ref.read(mushukistanApiProvider);
      final normalizedPhone =
          normalizeUzbekPhoneNumber(_phoneController.text.trim());
      await api.updateMe(
        name: _nameController.text.trim().isEmpty
            ? null
            : _nameController.text.trim(),
        bio: _bioController.text.trim().isEmpty
            ? ''
            : _bioController.text.trim(),
        phoneNumber: normalizedPhone ?? '',
        telegramUsername: _telegramController.text.trim().replaceFirst('@', ''),
      );
      ref.invalidate(profileMeProvider);
      if (mounted) {
        ref.read(editProfileHasUnsavedChangesProvider.notifier).state = false;
        final messenger = ScaffoldMessenger.of(context);
        final message = ref.read(appStringsProvider).changesSaved;
        setState(() => _exitApproved = true);
        context.pop();
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (error) {
      if (mounted) {
        final strings = ref.read(appStringsProvider);
        setState(() {
          _error = error is MushukistanApiException
              ? error.userMessage
              : strings.couldNotSaveChanges;
        });
        _syncUnsavedChanges();
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({
    required this.message,
    required this.onRetry,
    required this.retryLabel,
  });

  final String message;
  final VoidCallback onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: Text(retryLabel)),
          ],
        ),
      ),
    );
  }
}
