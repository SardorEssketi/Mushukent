import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/localization/account_security_strings.dart';
import '../../../../core/localization/language_controller.dart';
import '../../../../core/routing/auth_navigation.dart';
import '../../application/auth_controller.dart';
import '../../domain/auth_models.dart';
import '../widgets/google_sign_in_action.dart';
import '../widgets/legal_consent_text.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _acceptLegal = false;
  bool _submitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || ref.read(authControllerProvider).isBusy) return;
    final controller = ref.read(authControllerProvider.notifier);
    final strings = ref.read(appStringsProvider);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!_acceptLegal) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.acceptTermsAndPrivacy)),
      );
      return;
    }

    final registrationLanguage = ref.read(appLanguageProvider);
    try {
      _submitting = true;
      await controller.register(
        RegisterCredentials(
          name: _nameController.text.trim(),
          email: _emailController.text.trim(),
          password: _passwordController.text,
          preferredLanguage: registrationLanguage.code,
          acceptTerms: true,
          acceptPrivacy: true,
        ),
      );
    } on Object {
      // Surface handled by auth state.
    } finally {
      _submitting = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final strings = ref.watch(appStringsProvider);
    final isLoading = authState.isBusy || _submitting;
    final redirect = GoRouterState.of(context).uri.queryParameters['redirect'];

    return Scaffold(
      appBar: AppBar(title: Text(strings.createAccount)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ListView(
            padding: const EdgeInsets.all(24),
            shrinkWrap: true,
            children: [
              Text(
                strings.joinMushukistan,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 20),
              LegalAgreementText(
                prefixText: strings.googleLegalLeading,
                betweenText: strings.agreementBetween,
                firstLinkText: strings.termsOfService,
                secondLinkText: strings.privacyPolicy,
                suffixText: strings.googleLegalTrailing,
                enabled: !isLoading,
              ),
              const SizedBox(height: 12),
              GoogleSignInAction(enabled: !isLoading),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(strings.orContinueWithEmail),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 12),
              Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _nameController,
                      enabled: !isLoading,
                      textInputAction: TextInputAction.next,
                      decoration:
                          InputDecoration(labelText: strings.nameOptional),
                      validator: (value) => _validateName(value, strings),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _emailController,
                      enabled: !isLoading,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: strings.email,
                        hintText: strings.emailHint,
                      ),
                      validator: (value) => _validateEmail(value, strings),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      enabled: !isLoading,
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => unawaited(_submit()),
                      decoration: InputDecoration(
                        labelText: strings.password,
                        suffixIcon: IconButton(
                          onPressed: isLoading
                              ? null
                              : () => setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  }),
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                      validator: (value) => _validatePassword(value, strings),
                    ),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _acceptLegal,
                      onChanged: isLoading
                          ? null
                          : (value) => setState(() {
                                _acceptLegal = value ?? false;
                              }),
                      title: LegalAgreementText(
                        prefixText: strings.registrationLegalLeading,
                        betweenText: strings.agreementBetween,
                        firstLinkText: strings.termsOfService,
                        secondLinkText: strings.privacyPolicy,
                        suffixText: strings.registrationLegalTrailing,
                        enabled: !isLoading,
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    if (authState.hasError) ...[
                      const SizedBox(height: 8),
                      Text(
                        authState.message!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: isLoading ? null : () => unawaited(_submit()),
                      child: isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(strings.register),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: isLoading
                    ? null
                    : () => context.go(authEntryLocation('/login', redirect)),
                child: Text(strings.alreadyHaveAccount),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _validateName(String? value, AppStrings strings) {
    final name = value?.trim() ?? '';
    if (name.isEmpty) return strings.nameRequired;
    if (name.length > 100) return strings.nameTooLong;
    return null;
  }

  String? _validateEmail(String? value, AppStrings strings) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return strings.emailRequired;
    if (!email.contains('@')) return strings.invalidEmail;
    return null;
  }

  String? _validatePassword(String? value, AppStrings strings) {
    final password = value ?? '';
    if (password.isEmpty) return strings.passwordRequired;
    if (password.length < 8) return strings.passwordMin8;
    if (password.length > 128) {
      return ref.read(accountSecurityStringsProvider).passwordLength;
    }
    return null;
  }
}
