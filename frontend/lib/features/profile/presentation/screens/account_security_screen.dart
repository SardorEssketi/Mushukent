import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/localization/account_security_strings.dart';
import '../../../../core/localization/app_strings.dart';
import '../../../../core/network/api_error.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../../auth/application/auth_controller.dart';
import '../../../auth/infrastructure/account_security_repository.dart';

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

  Future<void> _savePassword() async {
    if (_busy || !(_formKey.currentState?.validate() ?? false)) return;
    final strings = ref.read(accountSecurityStringsProvider);
    setState(() {
      _busy = true;
      _error = null;
      _success = null;
    });
    try {
      final repository = ref.read(accountSecurityRepositoryProvider);
      await repository.changePassword(
          _current.text, _password.text, _confirmation.text);
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

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(accountSecurityStringsProvider);
    final user = ref.watch(currentUserProvider);
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
                Text(strings.emailAddress,
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: AppSpacing.lg),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(user?.email ?? strings.emailUnavailable),
                      const SizedBox(height: AppSpacing.xs),
                      Row(
                        children: [
                          Icon(
                            methods.emailVerified
                                ? Icons.verified_outlined
                                : Icons.info_outline,
                            size: 18,
                            color: methods.emailVerified
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Text(methods.emailVerified
                              ? strings.emailVerified
                              : strings.emailNeedsVerification),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                if (methods.hasPassword) ...[
                  Text(strings.password,
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: AppSpacing.lg),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.lock_outline),
                          title: Text(strings.password),
                          subtitle: Text(strings.passwordSet),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        if (!_editingPassword)
                          OutlinedButton(
                            onPressed: _busy
                                ? null
                                : () => setState(() {
                                      _editingPassword = true;
                                    }),
                            child: Text(strings.changePassword),
                          ),
                        if (_editingPassword)
                          Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
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
                                  onPressed: _busy ? null : _savePassword,
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
                ],
                TextButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          await ref
                              .read(authControllerProvider.notifier)
                              .logout();
                        },
                  child: Text(ref.watch(appStringsProvider).logout),
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
