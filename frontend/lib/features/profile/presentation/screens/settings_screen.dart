import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/localization/account_security_strings.dart';
import '../../../../core/localization/language_controller.dart';
import '../../../../core/navigation/settings_changes_guard.dart';
import '../../../../core/network/mushukistan_api.dart';
import '../../../../core/theme/theme_controller.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/widgets/app_surface.dart';
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
    ref.read(settingsHasUnsavedChangesProvider.notifier).state = false;
    ref.read(settingsDiscardChangesProvider.notifier).state =
        _discardPendingChanges;
  }

  void _discardPendingChanges() {
    final profile = ref.read(profileMeProvider).valueOrNull;
    if (!mounted) {
      return;
    }
    setState(() {
      _pendingTheme = ref.read(appThemeModeProvider);
      _pendingLanguage = ref.read(appLanguageProvider);
      _pendingAllowPublicActivityView =
          profile?.allowPublicActivityView ?? true;
    });
  }

  Future<bool> _confirmLeaving() {
    return confirmLeavingSettings(
      context,
      ref,
      onDiscard: _discardPendingChanges,
    );
  }

  Future<void> _openAboutAccount() async {
    if (!await _confirmLeaving() || !mounted) {
      return;
    }
    context.push('/profile/settings/about-account');
  }

  Future<void> _openAccountSecurity() async {
    if (!await _confirmLeaving() || !mounted) return;
    context.push('/profile/settings/security');
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
      await saveThemeMode(_pendingTheme);
      ref.read(appThemeModeProvider.notifier).state = _pendingTheme;
      ref.read(appLanguageProvider.notifier).state = _pendingLanguage;
      ref.read(settingsHasUnsavedChangesProvider.notifier).state = false;
      ref.invalidate(profileMeProvider);
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        final message = AppStrings.forLanguage(_pendingLanguage).changesSaved;
        context.go('/profile');
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (_) {
      ref.read(appThemeModeProvider.notifier).state = previousTheme;
      ref.read(appLanguageProvider.notifier).state = previousLanguage;
      ref.read(settingsHasUnsavedChangesProvider.notifier).state = _hasChanges;
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
    final securityStrings = ref.watch(accountSecurityStringsProvider);
    final hasChanges = _hasChanges;

    if (profile != null &&
        !_hasChanges &&
        _pendingAllowPublicActivityView != profile.allowPublicActivityView) {
      _pendingAllowPublicActivityView = profile.allowPublicActivityView;
    }

    if (ref.read(settingsHasUnsavedChangesProvider) != hasChanges) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(settingsHasUnsavedChangesProvider.notifier).state =
              _hasChanges;
        }
      });
    }

    return PopScope<void>(
      canPop: !hasChanges && !_isSaving,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || _isSaving) {
          return;
        }
        if (!await _confirmLeaving()) {
          return;
        }
        if (!context.mounted) {
          return;
        }
        context.pop();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(strings.settings)),
        body: AppContentWidth(
          maxWidth: AppWidths.compact,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Text(strings.theme,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              RadioGroup<AppThemeMode>(
                groupValue: _pendingTheme,
                onChanged: (value) {
                  if (!_isSaving && value != null) {
                    setState(() => _pendingTheme = value);
                    _updateUnsavedChanges();
                  }
                },
                child: Column(
                  children: [
                    RadioListTile(
                      contentPadding: EdgeInsets.zero,
                      value: AppThemeMode.original,
                      title: Text(strings.themeAuto),
                      secondary: const Icon(Icons.brightness_auto_outlined),
                    ),
                    RadioListTile(
                      contentPadding: EdgeInsets.zero,
                      value: AppThemeMode.dark,
                      title: Text(strings.themeDark),
                      secondary: const Icon(Icons.dark_mode_outlined),
                    ),
                    RadioListTile(
                      contentPadding: EdgeInsets.zero,
                      value: AppThemeMode.light,
                      title: Text(strings.themeLight),
                      secondary: const Icon(Icons.light_mode_outlined),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
              Text(
                strings.language,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.md),
              RadioGroup<AppLanguage>(
                groupValue: _pendingLanguage,
                onChanged: (value) {
                  if (!_isSaving && value != null) {
                    setState(() => _pendingLanguage = value);
                    _updateUnsavedChanges();
                  }
                },
                child: Column(
                  children: [
                    RadioListTile(
                      contentPadding: EdgeInsets.zero,
                      value: AppLanguage.english,
                      title: Text(strings.englishLanguage),
                    ),
                    RadioListTile(
                      contentPadding: EdgeInsets.zero,
                      value: AppLanguage.uzbek,
                      title: Text(strings.uzbekLanguage),
                    ),
                    RadioListTile(
                      contentPadding: EdgeInsets.zero,
                      value: AppLanguage.russian,
                      title: Text(strings.russianLanguage),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
              Text(
                strings.privacy,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
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
                        _updateUnsavedChanges();
                      },
              ),
              const SizedBox(height: AppSpacing.md),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.security_outlined),
                title: Text(securityStrings.title),
                trailing: const Icon(Icons.chevron_right),
                onTap: _isSaving ? null : _openAccountSecurity,
              ),
              const SizedBox(height: AppSpacing.md),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.info_outline),
                title: Text(strings.aboutAccount),
                trailing: const Icon(Icons.chevron_right),
                onTap: _isSaving ? null : _openAboutAccount,
              ),
              const SizedBox(height: AppSpacing.xl),
              FilledButton.icon(
                onPressed: hasChanges && !_isSaving ? _saveChanges : null,
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
        ),
      ),
    );
  }

  void _updateUnsavedChanges() {
    ref.read(settingsHasUnsavedChangesProvider.notifier).state = _hasChanges;
  }

  @override
  void dispose() {
    ref.read(settingsDiscardChangesProvider.notifier).state = null;
    ref.read(settingsHasUnsavedChangesProvider.notifier).state = false;
    super.dispose();
  }
}
