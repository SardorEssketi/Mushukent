import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/network/api_error.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../../auth/application/auth_controller.dart';

/// Shown to a signed-in user whose accepted Terms/Privacy Policy versions are outdated.
///
/// Acceptance is recorded only by tapping the button here; opening the app, signing in or reading
/// the documents never counts. Logging out and reading both documents stay available. The router
/// leaves this screen by itself once the server confirms the acceptance.
class LegalUpdateScreen extends ConsumerStatefulWidget {
  const LegalUpdateScreen({super.key});

  @override
  ConsumerState<LegalUpdateScreen> createState() => _LegalUpdateScreenState();
}

class _LegalUpdateScreenState extends ConsumerState<LegalUpdateScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _accept(AppStrings strings) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).acceptLegal();
    } on MushukistanApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.code == 'LEGAL_VERSION_MISMATCH'
            ? strings.legalUpdateChanged
            : strings.legalUpdateFailed;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = strings.legalUpdateFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final theme = Theme.of(context);
    // No app bar: the page heading below already carries the title, and in an app bar it was
    // truncated ("We updated our Terms and Priva...") on narrow phones.
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: AppContentWidth(
            maxWidth: 520,
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              children: [
                Text(strings.legalUpdateTitle,
                    style: theme.textTheme.headlineSmall),
                const SizedBox(height: AppSpacing.md),
                Text(strings.legalUpdateBody,
                    style: theme.textTheme.bodyLarge?.copyWith(height: 1.45)),
                const SizedBox(height: AppSpacing.lg),
                OutlinedButton(
                  onPressed: () => context.push('/legal/terms'),
                  child: Text(strings.termsOfService),
                ),
                const SizedBox(height: AppSpacing.sm),
                OutlinedButton(
                  onPressed: () => context.push('/legal/privacy'),
                  child: Text(strings.privacyPolicy),
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                FilledButton(
                  onPressed: _busy ? null : () => unawaited(_accept(strings)),
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(strings.legalUpdateAccept),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => unawaited(
                          ref.read(authControllerProvider.notifier).logout()),
                  child: Text(strings.logout),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
