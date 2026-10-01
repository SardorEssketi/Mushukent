import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/media/image_picker_options.dart';
import '../../../../core/media/selected_image_pipeline.dart';
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
  bool _pickingAvatar = false;
  String? _error;
  Uint8List? _avatarBytes;
  String? _avatarFilename;
  String? _avatarContentType;
  String _initialName = '';
  String _initialPhone = '';
  String _initialTelegram = '';
  String _initialBio = '';
  bool _exitApproved = false;
  bool _confirmingExit = false;

  @override
  void initState() {
    super.initState();
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
      (_avatarBytes != null ||
          _nameController.text != _initialName ||
          _phoneController.text != _initialPhone ||
          _telegramController.text != _initialTelegram ||
          _bioController.text != _initialBio);

  void _onInputChanged() {
    if (_initialised && mounted) setState(() {});
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
                  _AvatarEditor(
                    name: profile.name ?? profile.email,
                    email: profile.email,
                    avatarUrl: profile.avatarUrl,
                    avatarBytes: _avatarBytes,
                    onChange: _openAvatarPhotoSource,
                    picking: _pickingAvatar,
                    enabled: !_saving && !_pickingAvatar,
                    strings: strings,
                  ),
                  const SizedBox(height: AppSpacing.xl),
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
                      helperText: strings.uzbekPhoneFormatHelp,
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
                      hintText: strings.bioHint,
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
                      onPressed: _saving ? null : _saveProfile,
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
                        onPressed: _saving ? null : _saveProfile,
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

  Future<void> _openAvatarPhotoSource() async {
    if (_pickingAvatar || _saving) return;
    final strings = ref.read(appStringsProvider);
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(strings.profilePhoto,
                  style: Theme.of(sheetContext).textTheme.titleLarge),
              const SizedBox(height: AppSpacing.md),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: Text(strings.chooseFromGallery),
                onTap: () =>
                    Navigator.of(sheetContext).pop(ImageSource.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: Text(strings.takePhoto),
                onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || source == null) return;
    if (source == ImageSource.gallery) {
      await _pickAvatarFromGallery();
    } else {
      await _pickAvatarFromCamera();
    }
  }

  Future<void> _pickAvatarFromGallery() async {
    if (_pickingAvatar) {
      return;
    }
    setState(() {
      _pickingAvatar = true;
      _error = null;
    });
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: pickerImageQuality,
        maxWidth: pickerMaxWidth,
        maxHeight: pickerMaxHeight,
      );
      if (image == null) {
        return;
      }
      final avatar = await preparePickedXFileForUpload(
        image,
        preserveTransparency: true,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _avatarBytes = avatar.bytes;
        _avatarFilename = avatar.filename;
        _avatarContentType = avatar.contentType;
      });
    } catch (error) {
      logPhotoPipelineFailure('avatar_gallery_picker', error);
      if (mounted) {
        setState(() {
          _error = selectedImageErrorMessage(
            ref.read(appStringsProvider),
            error,
          );
        });
      }
    } finally {
      if (mounted) {
        setState(() => _pickingAvatar = false);
      }
    }
  }

  Future<void> _pickAvatarFromCamera() async {
    if (_pickingAvatar) {
      return;
    }
    setState(() {
      _pickingAvatar = true;
      _error = null;
    });
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: pickerImageQuality,
        maxWidth: pickerMaxWidth,
        maxHeight: pickerMaxHeight,
      );
      if (image == null) {
        return;
      }
      final avatar = await preparePickedXFileForUpload(
        image,
        preserveTransparency: true,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _avatarBytes = avatar.bytes;
        _avatarFilename = avatar.filename;
        _avatarContentType = avatar.contentType;
      });
    } catch (error) {
      logPhotoPipelineFailure('avatar_camera_picker', error);
      if (mounted) {
        setState(() {
          _error = selectedImageErrorMessage(
            ref.read(appStringsProvider),
            error,
          );
        });
      }
    } finally {
      if (mounted) {
        setState(() => _pickingAvatar = false);
      }
    }
  }

  Future<void> _saveProfile() async {
    if (_saving) {
      return;
    }
    if (!(_formKey.currentState?.validate() ?? true)) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    var avatarSaved = false;
    final hasAvatarDraft = _avatarBytes != null;
    try {
      final api = ref.read(mushukistanApiProvider);
      final avatarBytes = _avatarBytes;
      if (avatarBytes != null) {
        await api.updateAvatar(
          avatarBytes: avatarBytes,
          avatarFilename: _avatarFilename ?? 'avatar.jpg',
          avatarContentType: _avatarContentType ?? 'image/jpeg',
        );
        avatarSaved = true;
      }
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
        setState(() => _exitApproved = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) context.pop();
        });
      }
    } catch (error) {
      if (mounted) {
        final strings = ref.read(appStringsProvider);
        setState(() {
          if (avatarSaved) {
            _avatarBytes = null;
            _avatarFilename = null;
            _avatarContentType = null;
          }
          _error = avatarSaved
              ? strings.avatarSavedDetailsFailed
              : hasAvatarDraft
                  ? photoUploadErrorMessage(strings, error)
                  : error is MushukistanApiException
                      ? error.userMessage
                      : strings.couldNotSaveChanges;
        });
        if (avatarSaved) {
          ref.invalidate(profileMeProvider);
        }
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

class _AvatarEditor extends StatelessWidget {
  const _AvatarEditor({
    required this.name,
    required this.email,
    required this.avatarUrl,
    required this.avatarBytes,
    required this.onChange,
    required this.picking,
    required this.enabled,
    required this.strings,
  });

  final String name;
  final String email;
  final String? avatarUrl;
  final Uint8List? avatarBytes;
  final VoidCallback onChange;
  final bool picking;
  final bool enabled;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          _avatar(context),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(strings.profilePhoto,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                TextButton(
                  onPressed: enabled ? onChange : null,
                  child: Text(strings.changePhoto),
                ),
              ],
            ),
          ),
          if (picking)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }

  Widget _avatar(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fallback = CircleAvatar(
      radius: 44,
      backgroundColor: colors.primaryContainer,
      child: Text(
        _initials(name, email),
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: colors.onPrimaryContainer,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
    final bytes = avatarBytes;
    if (bytes != null) {
      return ClipOval(
        child: Image.memory(
          bytes,
          width: 88,
          height: 88,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback,
        ),
      );
    }
    final url = avatarUrl?.trim();
    if (url == null || url.isEmpty) return fallback;
    return ClipOval(
      child: Image.network(
        url,
        width: 88,
        height: 88,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
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

String _initials(String name, String email) {
  final source = name.trim().isEmpty ? email : name;
  final parts = source.split(RegExp(r'\s+')).where((part) => part.isNotEmpty);
  final initials = parts.take(2).map((part) => part[0]).join();
  return initials.isEmpty ? 'MU' : initials.toUpperCase();
}
