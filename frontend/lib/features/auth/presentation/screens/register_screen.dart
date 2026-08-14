import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/localization/language_controller.dart';
import '../../application/auth_controller.dart';
import '../../domain/auth_models.dart';
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
  bool _acceptTerms = false;
  bool _acceptPrivacy = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final controller = ref.read(authControllerProvider.notifier);
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    if (!_acceptTerms || !_acceptPrivacy) {
      final strings = ref.read(appStringsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(strings.acceptTermsAndPrivacy),
        ),
      );
      return;
    }

    final registrationLanguage = ref.read(appLanguageProvider);
    try {
      await controller.register(
        RegisterCredentials(
          name: _nameController.text.trim(),
          email: _emailController.text.trim(),
          password: _passwordController.text,
          preferredLanguage: registrationLanguage.code,
          acceptTerms: _acceptTerms,
          acceptPrivacy: _acceptPrivacy,
        ),
      );
    } on Object {
      // Surface handled by auth state.
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final strings = ref.watch(appStringsProvider);
    final isLoading = authState.phase == AuthPhase.authenticating;

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
              const SizedBox(height: 24),
              Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _nameController,
                      enabled: !isLoading,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: strings.nameOptional,
                      ),
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
                      onFieldSubmitted: (_) {
                        unawaited(_submit());
                      },
                      decoration: InputDecoration(
                        labelText: strings.password,
                        suffixIcon: IconButton(
                          onPressed: isLoading
                              ? null
                              : () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
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
                      value: _acceptTerms,
                      onChanged: isLoading
                          ? null
                          : (value) {
                              setState(() {
                                _acceptTerms = value ?? false;
                              });
                            },
                      title: LegalConsentText(
                        leadingText: strings.acceptLegalLeading,
                        linkText: strings.termsOfService,
                        trailingText: strings.acceptLegalTrailing,
                        route: '/legal/terms',
                        enabled: !isLoading,
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _acceptPrivacy,
                      onChanged: isLoading
                          ? null
                          : (value) {
                              setState(() {
                                _acceptPrivacy = value ?? false;
                              });
                            },
                      title: LegalConsentText(
                        leadingText: strings.acceptLegalLeading,
                        linkText: strings.privacyPolicy,
                        trailingText: strings.acceptLegalTrailing,
                        route: '/legal/privacy',
                        enabled: !isLoading,
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    if (authState.hasError) ...[
                      Text(
                        authState.message!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    FilledButton(
                      onPressed: isLoading
                          ? null
                          : () {
                              unawaited(_submit());
                            },
                      child: isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(strings.register),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: isLoading
                          ? null
                          : () {
                              context.go('/login');
                            },
                      child: Text(strings.alreadyHaveAccount),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _validateName(String? value, AppStrings strings) {
    final name = value?.trim() ?? '';
    if (name.isEmpty) {
      return strings.nameRequired;
    }
    if (name.length > 100) {
      return strings.nameTooLong;
    }
    return null;
  }

  String? _validateEmail(String? value, AppStrings strings) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) {
      return strings.emailRequired;
    }
    if (!email.contains('@')) {
      return strings.invalidEmail;
    }
    return null;
  }

  String? _validatePassword(String? value, AppStrings strings) {
    final password = value ?? '';
    if (password.isEmpty) {
      return strings.passwordRequired;
    }
    if (password.length < 8) {
      return strings.passwordMin8;
    }
    return null;
  }
}
