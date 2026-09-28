import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/network/api_error.dart';
import '../../../../core/network/mushukistan_api.dart';
import '../../../auth/application/auth_controller.dart';
import '../../../adoption_posts/presentation/screens/adoption_post_detail_screen.dart';
import '../screens/lost_pet_detail_screen.dart';

/// Checks the server for due prompts while the owner is using Mushukistan.
/// The server's persisted due_at is the only source of timing truth.
class LostPetFollowUpListener extends ConsumerStatefulWidget {
  const LostPetFollowUpListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<LostPetFollowUpListener> createState() =>
      _LostPetFollowUpListenerState();
}

class _LostPetFollowUpListenerState
    extends ConsumerState<LostPetFollowUpListener> with WidgetsBindingObserver {
  Timer? _checkTimer;
  bool _checking = false;
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => unawaited(_checkDue()),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_checkDue()));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_checkDue());
    }
  }

  @override
  void dispose() {
    _checkTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _checkDue() async {
    if (!mounted ||
        _checking ||
        _showing ||
        !ref.read(authControllerProvider).isAuthenticated) {
      return;
    }
    _checking = true;
    var recheck = false;
    try {
      List<LostPetFollowUpData> due;
      try {
        due = await ref.read(mushukistanApiProvider).listDueLostPetFollowUps();
      } catch (_) {
        due = const [];
      }
      if (!mounted) {
        return;
      }
      _showing = true;
      for (final followUp in due) {
        if (!mounted || !ref.read(authControllerProvider).isAuthenticated) {
          break;
        }
        if (await _showFollowUp(followUp)) {
          recheck = true;
          break;
        }
      }
      if (!recheck && mounted) {
        final adoptionDue =
            await ref.read(mushukistanApiProvider).listDueAdoptionFollowUps();
        for (final followUp in adoptionDue) {
          if (!mounted || !ref.read(authControllerProvider).isAuthenticated) {
            break;
          }
          if (await _showAdoptionFollowUp(followUp)) {
            recheck = true;
            break;
          }
        }
      }
    } catch (_) {
      // The next app check retries; due records remain persisted on the server.
    } finally {
      _checking = false;
      _showing = false;
      if (recheck && mounted) unawaited(_checkDue());
    }
  }

  Future<bool> _showFollowUp(LostPetFollowUpData followUp) async {
    final strings = ref.read(appStringsProvider);
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => PopScope(
            canPop: false,
            child: _FollowUpDialog(
              petName: followUp.petName,
              question: strings.didYouFindYourPet,
              strings: strings,
              answer: (yes) => ref
                  .read(mushukistanApiProvider)
                  .answerLostPetFollowUp(followUp.id, yes: yes),
              onAnswered: (result) {
                if (!mounted) return;
                final pet = result as LostPetData;
                ref.read(lostPetMutationOverridesProvider.notifier).state = {
                  ...ref.read(lostPetMutationOverridesProvider),
                  pet.id: pet,
                };
                ref.invalidate(lostPetDetailProvider(pet.id));
                if (pet.isResolved) {
                  ref.read(resolvedLostPetIdsProvider.notifier).state = {
                    ...ref.read(resolvedLostPetIdsProvider),
                    pet.id,
                  };
                }
                ref.read(postMutationRevisionProvider.notifier).state++;
              },
              onAlreadyCompleted: () {
                if (!mounted) return;
                ref.invalidate(lostPetDetailProvider(followUp.lostPetId));
                ref.read(postMutationRevisionProvider.notifier).state++;
              },
            ),
          ),
        ) ??
        false;
  }

  Future<bool> _showAdoptionFollowUp(AdoptionFollowUpData followUp) async {
    final strings = ref.read(appStringsProvider);
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => PopScope(
            canPop: false,
            child: _FollowUpDialog(
              petName: followUp.petName,
              question: strings.didYourPetFindNewHome,
              strings: strings,
              answer: (yes) => ref
                  .read(mushukistanApiProvider)
                  .answerAdoptionFollowUp(followUp.id, yes: yes),
              onAnswered: (result) {
                if (!mounted) return;
                final post = result as AdoptionPostData;
                ref.read(adoptionMutationOverridesProvider.notifier).state = {
                  ...ref.read(adoptionMutationOverridesProvider),
                  post.id: post,
                };
                ref.invalidate(adoptionPostDetailProvider(post.id));
                if (post.isResolved) {
                  ref.read(resolvedAdoptionIdsProvider.notifier).state = {
                    ...ref.read(resolvedAdoptionIdsProvider),
                    post.id,
                  };
                }
                ref.read(postMutationRevisionProvider.notifier).state++;
              },
              onAlreadyCompleted: () {
                if (!mounted) return;
                ref.invalidate(
                    adoptionPostDetailProvider(followUp.adoptionPostId));
                ref.read(postMutationRevisionProvider.notifier).state++;
              },
            ),
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AuthState>(authControllerProvider, (previous, next) {
      if (previous?.isAuthenticated != true && next.isAuthenticated) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => unawaited(_checkDue()));
      }
    });
    return widget.child;
  }
}

class _FollowUpDialog extends ConsumerStatefulWidget {
  const _FollowUpDialog({
    required this.petName,
    required this.question,
    required this.answer,
    required this.strings,
    required this.onAnswered,
    required this.onAlreadyCompleted,
  });

  final String petName;
  final String question;
  final Future<Object> Function(bool yes) answer;
  final AppStrings strings;
  final ValueChanged<Object> onAnswered;
  final VoidCallback onAlreadyCompleted;

  @override
  ConsumerState<_FollowUpDialog> createState() => _FollowUpDialogState();
}

class _FollowUpDialogState extends ConsumerState<_FollowUpDialog> {
  bool _submitting = false;

  Future<void> _answer(bool yes) async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      final pet = await widget.answer(yes);
      widget.onAnswered(pet);
      if (mounted) Navigator.of(context).pop(false);
    } on MushukistanApiException catch (error) {
      if (error.code == 'FOLLOW_UP_COMPLETED' ||
          error.code == 'FOLLOW_UP_NOT_FOUND') {
        widget.onAlreadyCompleted();
        if (mounted) Navigator.of(context).pop(true);
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.strings.couldNotSaveChanges)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.strings.couldNotSaveChanges)),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.question),
      content: Text(widget.petName),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => _answer(false),
          child: Text(widget.strings.followUpNo),
        ),
        FilledButton(
          onPressed: _submitting ? null : () => _answer(true),
          child: Text(widget.strings.followUpYes),
        ),
      ],
    );
  }
}
