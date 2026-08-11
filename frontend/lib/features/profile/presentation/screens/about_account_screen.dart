import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/network/mushukistan_api.dart';
import '../../../auth/application/auth_controller.dart';
import 'profile_screen.dart';

class AboutAccountScreen extends ConsumerStatefulWidget {
  const AboutAccountScreen({super.key});

  @override
  ConsumerState<AboutAccountScreen> createState() => _AboutAccountScreenState();
}

class _AboutAccountScreenState extends ConsumerState<AboutAccountScreen> {
  bool _isDeleting = false;

  Future<void> _deleteAccount() async {
    if (_isDeleting) {
      return;
    }

    final strings = ref.read(appStringsProvider);
    final confirmed = await _confirmDeleteAccount(context, strings);
    if (!confirmed || !mounted) {
      return;
    }

    setState(() {
      _isDeleting = true;
    });

    try {
      await ref.read(mushukistanApiProvider).deleteMe();
      ref.invalidate(profileMeProvider);
      await ref.read(authControllerProvider.notifier).logout();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.accountDeleted)),
        );
        context.go('/login');
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.couldNotDeleteAccount)),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDeleting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final profileAsync = ref.watch(profileMeProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(strings.aboutAccount)),
      body: profileAsync.when(
        data: (profile) => ListView(
          padding: const EdgeInsets.all(24),
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today_outlined),
              title: Text(strings.registered),
              subtitle: Text(_formatDate(profile.registeredAt)),
            ),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.alternate_email_outlined),
              title: Text(strings.email),
              subtitle: Text(profile.email),
            ),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.phone_outlined),
              title: Text(strings.phoneNumber),
              subtitle: Text(_phoneNumberLabel(profile.phoneNumber, strings)),
            ),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.policy_outlined),
              title: Text(strings.privacyPolicy),
              subtitle: Text(strings.privacyPolicySummary),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/legal/privacy'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.article_outlined),
              title: Text(strings.termsOfService),
              subtitle: Text(strings.termsOfServiceSummary),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/legal/terms'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.delete_outline, color: colorScheme.error),
              title: Text(
                strings.accountDeletion,
                style: TextStyle(color: colorScheme.error),
              ),
              subtitle: Text(strings.accountDeletionSummary),
              trailing: _isDeleting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.chevron_right, color: colorScheme.error),
              onTap: _isDeleting ? null : _deleteAccount,
            ),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(child: Text(error.toString())),
      ),
    );
  }
}

Future<bool> _confirmDeleteAccount(
  BuildContext context,
  AppStrings strings,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => _DeleteAccountConfirmationDialog(
      strings: strings,
    ),
  );

  return confirmed ?? false;
}

class _DeleteAccountConfirmationDialog extends StatefulWidget {
  const _DeleteAccountConfirmationDialog({required this.strings});

  final AppStrings strings;

  @override
  State<_DeleteAccountConfirmationDialog> createState() =>
      _DeleteAccountConfirmationDialogState();
}

class _DeleteAccountConfirmationDialogState
    extends State<_DeleteAccountConfirmationDialog> {
  static const _confirmationDelaySeconds = 5;

  Timer? _timer;
  int _secondsRemaining = _confirmationDelaySeconds;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining <= 1) {
        timer.cancel();
        if (mounted) {
          setState(() {
            _secondsRemaining = 0;
          });
        }
        return;
      }

      if (mounted) {
        setState(() {
          _secondsRemaining -= 1;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Text(widget.strings.confirmDeleteAccountTitle),
      content: Text(widget.strings.confirmDeleteAccountMessage),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(widget.strings.cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: colorScheme.error,
            foregroundColor: colorScheme.onError,
          ),
          onPressed: _secondsRemaining == 0
              ? () => Navigator.of(context).pop(true)
              : null,
          child: Text(
            _secondsRemaining == 0
                ? widget.strings.deleteAccount
                : '${widget.strings.deleteAccount} ($_secondsRemaining)',
          ),
        ),
      ],
    );
  }
}

String _formatDate(DateTime dateTime) {
  final local = dateTime.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}

String _phoneNumberLabel(String? phoneNumber, AppStrings strings) {
  final trimmed = phoneNumber?.trim() ?? '';
  return trimmed.isEmpty ? strings.notAdded : trimmed;
}
