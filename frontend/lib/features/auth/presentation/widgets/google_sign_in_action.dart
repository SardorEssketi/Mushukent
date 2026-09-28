import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/network/api_error.dart';
import '../../application/auth_controller.dart';
import 'google_sign_in_entry_button.dart';

/// The token exists only for this sign-in attempt, including password confirmation.
class GoogleSignInAction extends ConsumerStatefulWidget {
  const GoogleSignInAction({super.key, required this.enabled});

  final bool enabled;

  @override
  ConsumerState<GoogleSignInAction> createState() => _GoogleSignInActionState();
}

class _GoogleSignInActionState extends ConsumerState<GoogleSignInAction> {
  bool _busy = false;

  Future<void> _signIn(
      BuildContext context, WidgetRef ref, String token) async {
    try {
      await ref
          .read(authControllerProvider.notifier)
          .loginWithGoogleIdToken(token);
    } on MushukistanApiException catch (error) {
      if (error.code == 'GOOGLE_PASSWORD_REQUIRED' && context.mounted) {
        await _confirmPassword(token);
      }
    }
  }

  Future<void> _confirmPassword(String token) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ConfirmPassword(token: token),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return GoogleSignInEntryButton(
        enabled: widget.enabled && !_busy,
        onIdToken: (token) => _signIn(context, ref, token),
      );
    }
    return OutlinedButton.icon(
      onPressed: !widget.enabled || _busy
          ? null
          : () async {
              setState(() => _busy = true);
              try {
                await ref.read(authControllerProvider.notifier).loginWithGoogle(
                      onPasswordRequired: _confirmPassword,
                    );
              } on Object {
                // AuthController exposes the sign-in error.
              } finally {
                if (mounted) setState(() => _busy = false);
              }
            },
      icon: const Icon(Icons.login),
      label: Text(ref.watch(appStringsProvider).continueWithGoogle),
    );
  }
}

class _ConfirmPassword extends ConsumerStatefulWidget {
  const _ConfirmPassword({required this.token});
  final String token;

  @override
  ConsumerState<_ConfirmPassword> createState() => _ConfirmPasswordState();
}

class _ConfirmPasswordState extends ConsumerState<_ConfirmPassword> {
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || _password.text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).loginWithGoogleIdToken(
            widget.token,
            password: _password.text,
          );
      if (mounted) Navigator.of(context).pop();
    } on MushukistanApiException catch (error) {
      if (mounted) setState(() => _error = error.userMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(strings.confirmSignInPassword),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(strings.confirmSignInPasswordHelp),
            TextField(
              controller: _password,
              enabled: !_busy,
              obscureText: true,
              autofocus: true,
              decoration: InputDecoration(labelText: strings.password),
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null)
              Text(_error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  )),
          ],
        ),
        actions: [
          TextButton(
              onPressed: _busy
                  ? null
                  : () {
                      ref
                          .read(authControllerProvider.notifier)
                          .showUnauthenticatedMessage('');
                      Navigator.of(context).pop();
                    },
              child: Text(strings.cancel)),
          FilledButton(
              onPressed: _busy ? null : _submit,
              child: Text(strings.continueAction)),
        ],
      ),
    );
  }
}
