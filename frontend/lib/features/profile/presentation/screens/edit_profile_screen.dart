import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/network/api_error.dart';
import '../../../../core/network/mushukistan_api.dart';
import '../../../../core/validation/phone_numbers.dart';
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
  Uint8List? _avatarBytes;
  String? _avatarFilename;
  String? _avatarContentType;

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
    if (!_initialised && profileAsync.hasValue) {
      final profile = profileAsync.value!;
      _nameController.text = profile.name ?? '';
      _phoneController.text = profile.phoneNumber ?? '';
      _telegramController.text = profile.telegramUsername ?? '';
      _bioController.text = profile.bio ?? '';
      _initialised = true;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      body: profileAsync.when(
        data: (profile) => Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _AvatarEditor(
                name: profile.name ?? profile.email,
                email: profile.email,
                avatarUrl: profile.avatarUrl,
                avatarBytes: _avatarBytes,
                onGallery: _pickAvatarFromGallery,
                onCamera: _pickAvatarFromCamera,
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Name'),
                maxLength: 100,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(
                  labelText: 'Phone number',
                  hintText: '+998 99 142 1314',
                  helperText: 'Uzbekistan format: +998 XX XXX XXXX',
                ),
                keyboardType: TextInputType.phone,
                maxLength: 32,
                validator: (value) {
                  final phone = value?.trim() ?? '';
                  if (phone.isEmpty) {
                    return null;
                  }
                  return isValidUzbekPhoneNumber(phone)
                      ? null
                      : invalidUzbekPhoneMessage;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _telegramController,
                decoration: const InputDecoration(
                  labelText: 'Telegram username',
                  hintText: 'sardor_dev',
                  prefixText: '@',
                ),
                maxLength: 32,
                validator: (value) {
                  final username = value?.trim().replaceFirst('@', '') ?? '';
                  if (username.isEmpty) {
                    return null;
                  }
                  final valid =
                      RegExp(r'^[A-Za-z0-9_]{5,32}$').hasMatch(username);
                  return valid
                      ? null
                      : 'Use 5-32 letters, numbers, or underscores.';
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _bioController,
                decoration: const InputDecoration(
                  labelText: 'Bio',
                  hintText: 'Aydos from Tashkent, cat lover',
                ),
                maxLines: 4,
                maxLength: 1000,
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _saving ? null : _saveProfile,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save changes'),
              ),
            ],
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => _ErrorPanel(
          message: error.toString(),
          onRetry: () => ref.invalidate(profileMeProvider),
        ),
      ),
    );
  }

  Future<void> _pickAvatarFromGallery() async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file = result?.files.singleOrNull;
    final bytes = file?.bytes;
    if (file == null || bytes == null) {
      return;
    }
    setState(() {
      _avatarBytes = bytes;
      _avatarFilename = file.name;
      _avatarContentType = _contentTypeFor(file.extension, file.name);
    });
  }

  Future<void> _pickAvatarFromCamera() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
    );
    if (image == null) {
      return;
    }
    final bytes = await image.readAsBytes();
    setState(() {
      _avatarBytes = bytes;
      _avatarFilename = image.name;
      _avatarContentType = image.mimeType ?? _contentTypeFor(null, image.name);
    });
  }

  Future<void> _saveProfile() async {
    if (!(_formKey.currentState?.validate() ?? true)) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final api = ref.read(mushukistanApiProvider);
      final avatarBytes = _avatarBytes;
      if (avatarBytes != null) {
        await api.updateAvatar(
          avatarBytes: avatarBytes,
          avatarFilename: _avatarFilename ?? 'avatar.jpg',
          avatarContentType: _avatarContentType ?? 'image/jpeg',
        );
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
        context.pop();
      }
    } catch (error) {
      setState(() {
        _error = error is MushukistanApiException
            ? error.userMessage
            : error.toString();
      });
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
    required this.onGallery,
    required this.onCamera,
  });

  final String name;
  final String email;
  final String? avatarUrl;
  final Uint8List? avatarBytes;
  final VoidCallback onGallery;
  final VoidCallback onCamera;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            CircleAvatar(
              radius: 44,
              backgroundImage: _avatarImage(),
              child:
                  _avatarImage() == null ? Text(_initials(name, email)) : null,
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: onGallery,
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Change profile picture'),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onCamera,
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Use camera'),
            ),
          ],
        ),
      ),
    );
  }

  ImageProvider? _avatarImage() {
    final bytes = avatarBytes;
    if (bytes != null) {
      return MemoryImage(bytes);
    }
    if (avatarUrl != null) {
      return NetworkImage(avatarUrl!);
    }
    return null;
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

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
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

String _contentTypeFor(String? extension, String filename) {
  final ext = (extension ?? '').toLowerCase();
  if (ext == 'png') {
    return 'image/png';
  }
  if (ext == 'jpg' || ext == 'jpeg') {
    return 'image/jpeg';
  }
  if (filename.toLowerCase().endsWith('.png')) {
    return 'image/png';
  }
  return 'image/jpeg';
}

String _initials(String name, String email) {
  final source = name.trim().isEmpty ? email : name;
  final parts = source.split(RegExp(r'\s+')).where((part) => part.isNotEmpty);
  final initials = parts.take(2).map((part) => part[0]).join();
  return initials.isEmpty ? 'MU' : initials.toUpperCase();
}
