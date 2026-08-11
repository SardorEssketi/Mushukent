import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../application/auth_controller.dart';
import '../../domain/auth_models.dart';
import '../widgets/google_sign_in_entry_button.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final controller = ref.read(authControllerProvider.notifier);
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    try {
      await controller.login(
        AuthCredentials(
          email: _emailController.text.trim(),
          password: _passwordController.text,
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
      appBar: AppBar(title: Text(strings.welcomeBack)),
      body: Center(
        child: AppContentWidth(
          maxWidth: 440,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            shrinkWrap: true,
            children: [
              Text(
                strings.signInToMushukistan,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Access your posts, alerts, profile, and community activity.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: AppSpacing.xl),
              AppCard(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
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
                      const SizedBox(height: AppSpacing.lg),
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
                      const SizedBox(height: AppSpacing.lg),
                      if (authState.hasError) ...[
                        Text(
                          authState.message!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
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
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(strings.login),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      if (kIsWeb)
                        GoogleSignInEntryButton(enabled: !isLoading)
                      else
                        OutlinedButton(
                          onPressed: isLoading
                              ? null
                              : () async {
                                  try {
                                    await ref
                                        .read(authControllerProvider.notifier)
                                        .loginWithGoogle();
                                  } on Object {
                                    // Surface handled by auth state.
                                  }
                                },
                          child: Text(strings.continueWithGoogle),
                        ),
                      const SizedBox(height: AppSpacing.md),
                      TextButton(
                        onPressed: isLoading
                            ? null
                            : () {
                                context.go('/register');
                              },
                        child: Text(strings.createAnAccount),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
    if ((value ?? '').isEmpty) {
      return strings.passwordRequired;
    }
    return null;
  }
}
