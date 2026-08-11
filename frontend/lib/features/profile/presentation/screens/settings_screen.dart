import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/localization/language_controller.dart';
import '../../../../core/network/mushukistan_api.dart';
import '../../../../core/theme/theme_controller.dart';
import 'profile_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late AppThemeMode _pendingTheme;
  late AppLanguage _pendingLanguage;
  late bool _pendingAllowPublicActivityView;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _pendingTheme = ref.read(appThemeModeProvider);
    _pendingLanguage = ref.read(appLanguageProvider);
    final profile = ref.read(profileMeProvider).valueOrNull;
    _pendingAllowPublicActivityView = profile?.allowPublicActivityView ?? true;
  }

  bool get _hasChanges {
    final profile = ref.read(profileMeProvider).valueOrNull;
    return _pendingTheme != ref.read(appThemeModeProvider) ||
        _pendingLanguage != ref.read(appLanguageProvider) ||
        (profile != null &&
            _pendingAllowPublicActivityView != profile.allowPublicActivityView);
  }

  Future<void> _saveChanges() async {
    if (!_hasChanges || _isSaving) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    final previousTheme = ref.read(appThemeModeProvider);
    final previousLanguage = ref.read(appLanguageProvider);
    try {
      await ref.read(mushukistanApiProvider).updateMe(
            preferredLanguage: _pendingLanguage.code,
            allowPublicActivityView: _pendingAllowPublicActivityView,
          );
      ref.read(appThemeModeProvider.notifier).state = _pendingTheme;
      ref.read(appLanguageProvider.notifier).state = _pendingLanguage;
      ref.invalidate(profileMeProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(AppStrings.forLanguage(_pendingLanguage).changesSaved),
          ),
        );
        context.go('/profile');
      }
    } catch (_) {
      ref.read(appThemeModeProvider.notifier).state = previousTheme;
      ref.read(appLanguageProvider.notifier).state = previousLanguage;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.forLanguage(previousLanguage).couldNotSaveChanges,
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(appThemeModeProvider);
    ref.watch(appLanguageProvider);
    final profile = ref.watch(profileMeProvider).valueOrNull;
    final strings = ref.watch(appStringsProvider);

    if (profile != null &&
        !_hasChanges &&
        _pendingAllowPublicActivityView != profile.allowPublicActivityView) {
      _pendingAllowPublicActivityView = profile.allowPublicActivityView;
    }

    return Scaffold(
      appBar: AppBar(title: Text(strings.settings)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(strings.theme, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          SegmentedButton<AppThemeMode>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: AppThemeMode.original,
                label: Text(strings.themeAuto),
                icon: const Icon(Icons.brightness_auto_outlined),
              ),
              ButtonSegment(
                value: AppThemeMode.dark,
                label: Text(strings.themeDark),
                icon: const Icon(Icons.dark_mode_outlined),
              ),
              ButtonSegment(
                value: AppThemeMode.light,
                label: Text(strings.themeLight),
                icon: const Icon(Icons.light_mode_outlined),
              ),
            ],
            selected: {_pendingTheme},
            onSelectionChanged: (selection) {
              setState(() {
                _pendingTheme = selection.first;
              });
            },
          ),
          const SizedBox(height: 28),
          Text(strings.language,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          SegmentedButton<AppLanguage>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: AppLanguage.english,
                label: Text('English'),
                icon: Icon(Icons.language_outlined),
              ),
              ButtonSegment(
                value: AppLanguage.uzbek,
                label: Text('Uzbek'),
                icon: Icon(Icons.language_outlined),
              ),
              ButtonSegment(
                value: AppLanguage.russian,
                label: Text('Russian'),
                icon: Icon(Icons.language_outlined),
              ),
            ],
            selected: {_pendingLanguage},
            onSelectionChanged: (selection) {
              setState(() {
                _pendingLanguage = selection.first;
              });
            },
          ),
          const SizedBox(height: 28),
          Text(strings.privacy, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(strings.allowPublicActivityView),
            subtitle: Text(strings.allowPublicActivityViewSubtitle),
            value: _pendingAllowPublicActivityView,
            onChanged: _isSaving
                ? null
                : (value) {
                    setState(() {
                      _pendingAllowPublicActivityView = value;
                    });
                  },
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.info_outline),
            title: Text(strings.aboutAccount),
            trailing: const Icon(Icons.chevron_right),
            onTap: _isSaving
                ? null
                : () {
                    context.push('/profile/settings/about-account');
                  },
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _hasChanges && !_isSaving ? _saveChanges : null,
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(strings.saveChanges),
          ),
        ],
      ),
    );
  }
}
