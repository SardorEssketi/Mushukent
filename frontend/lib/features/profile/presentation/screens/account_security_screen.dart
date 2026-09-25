import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/localization/account_security_strings.dart';
import '../../../../core/network/api_error.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../../auth/application/auth_controller.dart';
import '../../../auth/infrastructure/account_security_repository.dart';
import '../../../auth/presentation/widgets/google_sign_in_entry_button.dart';

class AccountSecurityScreen extends ConsumerStatefulWidget {
  const AccountSecurityScreen({super.key});

  @override
  ConsumerState<AccountSecurityScreen> createState() =>
      _AccountSecurityScreenState();
}

class _AccountSecurityScreenState extends ConsumerState<AccountSecurityScreen> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  late Future<SignInMethods> _methods;
  bool _busy = false;
  bool _googleInProgress = false;
  bool _editingPassword = false;
  bool _showPassword = false;
  String? _error;
  String? _success;

  @override
  void initState() {
    super.initState();
    _methods = ref.read(accountSecurityRepositoryProvider).getMethods();
  }

  @override
  void dispose() {
    _current.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _methods = ref.read(accountSecurityRepositoryProvider).getMethods();
    });
  }

  Future<void> _savePassword(bool hasPassword) async {
    if (_busy || !(_formKey.currentState?.validate() ?? false)) return;
    final strings = ref.read(accountSecurityStringsProvider);
    setState(() {
      _busy = true;
      _error = null;
      _success = null;
    });
    try {
      final repository = ref.read(accountSecurityRepositoryProvider);
      if (hasPassword) {
        await repository.changePassword(
            _current.text, _password.text, _confirmation.text);
      } else {
        await repository.setPassword(_password.text, _confirmation.text);
      }
      _current.clear();
      _password.clear();
      _confirmation.clear();
      if (!mounted) return;
      setState(() {
        _editingPassword = false;
        _success = strings.saved;
      });
      _reload();
    } on MushukistanApiException catch (error) {
      if (mounted) setState(() => _error = error.userMessage);
    } on Object {
      if (mounted) setState(() => _error = strings.loadFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connectGoogleToken(String idToken) async {
    if (_busy) return;
    final strings = ref.read(accountSecurityStringsProvider);
    setState(() {
      _busy = true;
      _error = null;
      _success = null;
    });
    try {
      await ref.read(accountSecurityRepositoryProvider).connectGoogle(idToken);
      if (!mounted) return;
      setState(() => _success = strings.connectionSaved);
      _reload();
    } on MushukistanApiException catch (error) {
      if (mounted) setState(() => _error = error.userMessage);
    } on Object {
      if (mounted) setState(() => _error = strings.loadFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connectGoogleNative() async {
    if (_busy || _googleInProgress) return;
    setState(() {
      _googleInProgress = true;
      _error = null;
    });
    try {
      final token = await ref.read(googleIdentityTokenProvider).authenticate();
      if (mounted) await _connectGoogleToken(token);
    } on Object {
      if (mounted) {
        setState(() =>
            _error = ref.read(accountSecurityStringsProvider).googleFailed);
      }
    } finally {
      if (mounted) setState(() => _googleInProgress = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(accountSecurityStringsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(strings.title)),
      body: AppContentWidth(
        maxWidth: AppWidths.compact,
        child: FutureBuilder<SignInMethods>(
          future: _methods,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              if (snapshot.hasError) {
                return Center(
                  child: TextButton(
                    onPressed: _reload,
                    child: Text(strings.loadFailed),
                  ),
                );
              }
              return const Center(child: CircularProgressIndicator());
            }
            final methods = snapshot.data!;
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                Text(strings.signInMethods,
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: AppSpacing.lg),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.account_circle_outlined),
                        title: Text(strings.google),
                        subtitle: Text(methods.googleConnected
                            ? strings.connected
                            : strings.notConnected),
                      ),
                      if (!methods.googleConnected)
                        kIsWeb
                            ? GoogleSignInEntryButton(
                                enabled: !_busy,
                                onIdToken: _connectGoogleToken,
                                onError: (_) => setState(
                                    () => _error = strings.googleFailed))
                            : OutlinedButton(
                                onPressed: _busy || _googleInProgress
                                    ? null
                                    : _connectGoogleNative,
                                child: Text(strings.connectGoogle),
                              ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.lock_outline),
                        title: Text(strings.password),
                        subtitle: Text(methods.hasPassword
                            ? strings.passwordSet
                            : strings.passwordNotSet),
                      ),
                      Text(strings.separatePassword),
                      const SizedBox(height: AppSpacing.md),
                      if (!_editingPassword)
                        OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() => _editingPassword = true),
                          child: Text(methods.hasPassword
                              ? strings.changePassword
                              : strings.setPassword),
                        ),
                      if (_editingPassword)
                        Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (methods.hasPassword) ...[
                                TextFormField(
                                  controller: _current,
                                  enabled: !_busy,
                                  obscureText: !_showPassword,
                                  decoration: InputDecoration(
                                      labelText: strings.currentPassword),
                                  validator: (value) =>
                                      value?.isNotEmpty == true
                                          ? null
                                          : strings.required,
                                ),
                                const SizedBox(height: AppSpacing.sm),
                              ],
                              TextFormField(
                                controller: _password,
                                enabled: !_busy,
                                obscureText: !_showPassword,
                                decoration: InputDecoration(
                                  labelText: strings.newPassword,
                                  suffixIcon: IconButton(
                                    onPressed: _busy
                                        ? null
                                        : () => setState(() =>
                                            _showPassword = !_showPassword),
                                    icon: Icon(_showPassword
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined),
                                  ),
                                ),
                                validator: (value) => value != null &&
                                        value.length >= 8 &&
                                        value.length <= 128
                                    ? null
                                    : strings.passwordLength,
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              TextFormField(
                                controller: _confirmation,
                                enabled: !_busy,
                                obscureText: !_showPassword,
                                decoration: InputDecoration(
                                    labelText: strings.confirmPassword),
                                validator: (value) => value == _password.text
                                    ? null
                                    : strings.passwordMismatch,
                              ),
                              const SizedBox(height: AppSpacing.md),
                              FilledButton(
                                onPressed: _busy
                                    ? null
                                    : () => _savePassword(methods.hasPassword),
                                child: _busy
                                    ? const CircularProgressIndicator()
                                    : Text(strings.save),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ],
                if (_success != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(_success!),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
