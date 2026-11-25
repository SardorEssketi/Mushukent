import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../profile/presentation/screens/profile_screen.dart';

/// One line above Publish on Lost Pet and Rehoming posts: the profile phone
/// (and Telegram) is the consent, so the form names what signed-in users will
/// see (docs/CONTACT_PRIVACY.md). Shows nothing until the profile has loaded
/// or when the profile has no phone (the server then refuses the post).
class ContactShareNotice extends ConsumerWidget {
  const ContactShareNotice({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final profile = ref.watch(profileMeProvider).valueOrNull;
    final phone = profile?.phoneNumber?.trim() ?? '';
    if (phone.isEmpty) return const SizedBox.shrink();
    final telegram = profile?.telegramUsername?.trim() ?? '';
    final colors = Theme.of(context).colorScheme;
    return Padding(
      key: const ValueKey('contact-share-notice'),
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline, size: 18, color: colors.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              telegram.isEmpty
                  ? strings.contactNoticePhone(phone)
                  : strings.contactNoticePhoneAndTelegram(phone),
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
