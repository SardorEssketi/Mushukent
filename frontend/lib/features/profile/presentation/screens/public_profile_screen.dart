import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/network/api_error.dart';
import '../../../../core/network/mushukistan_api.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/widgets/app_surface.dart';

class PublicProfileBundle {
  const PublicProfileBundle({
    required this.profile,
    required this.posts,
  });

  final UserPublicData profile;
  final ApiPage<PostSummary> posts;
}

final publicProfileProvider =
    FutureProvider.autoDispose.family<PublicProfileBundle?, String>(
  (ref, userId) async {
    final api = ref.watch(mushukistanApiProvider);
    final profile = await api.getPublicProfile(userId);
    ApiPage<PostSummary> posts;
    try {
      posts = await api.listPublicProfilePosts(userId, limit: 20);
    } on MushukistanApiException catch (error) {
      if (error.code != 'ACTIVITY_PRIVATE') {
        rethrow;
      }
      posts = const ApiPage<PostSummary>(items: [], limit: 20);
    }
    return PublicProfileBundle(profile: profile, posts: posts);
  },
);

class PublicProfileScreen extends ConsumerStatefulWidget {
  const PublicProfileScreen({super.key, required this.userId});

  final String userId;

  @override
  ConsumerState<PublicProfileScreen> createState() =>
      _PublicProfileScreenState();
}

class _PublicProfileScreenState extends ConsumerState<PublicProfileScreen> {
  bool _isBlocking = false;

  @override
  Widget build(BuildContext context) {
    final userId = widget.userId;
    final profileAsync = ref.watch(publicProfileProvider(userId));
    final strings = ref.watch(appStringsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(strings.profile)),
      body: profileAsync.when(
        data: (result) {
          if (result == null) {
            return AppStatePanel(
              icon: Icons.person_off_outlined,
              title: strings.profile,
              message: strings.profileNotFound,
            );
          }
          final profile = result.profile;
          final posts = result.posts;
          return AppContentWidth(
            maxWidth: AppWidths.readable,
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundImage: profile.avatarUrl == null
                          ? null
                          : NetworkImage(profile.avatarUrl!),
                      child: profile.avatarUrl == null
                          ? Text(_initials(profile.name))
                          : null,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            profile.name ?? strings.unnamedUser,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            '${profile.observationCount} ${strings.observations}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.pets_outlined),
                  title: Text(strings.userObservations),
                  trailing: const Icon(Icons.chevron_right),
                  enabled: profile.allowPublicActivityView,
                  onTap: profile.allowPublicActivityView
                      ? () => context.push('/users/${profile.id}/observations')
                      : null,
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.chat_bubble_outline),
                  title: Text(strings.userComments),
                  trailing: const Icon(Icons.chevron_right),
                  enabled: profile.allowPublicActivityView,
                  onTap: profile.allowPublicActivityView
                      ? () => context.push('/users/${profile.id}/comments')
                      : null,
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.flag_outlined),
                  title: Text(strings.report),
                  onTap: () => context.push(
                    Uri(
                      path: '/report',
                      queryParameters: {
                        'type': 'user',
                        'id': profile.id,
                        'label': profile.name ?? strings.unnamedUser,
                      },
                    ).toString(),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: _isBlocking
                      ? const SizedBox.square(
                          dimension: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.block_outlined),
                  title: Text(strings.blockUser),
                  enabled: !_isBlocking,
                  onTap: _isBlocking
                      ? null
                      : () => _blockProfile(profile.id, strings),
                ),
                const SizedBox(height: AppSpacing.lg),
                if (!profile.allowPublicActivityView)
                  Text(strings.noActivityVisible)
                else if (posts.items.isEmpty)
                  Text(strings.noObservationsYet)
                else
                  ...posts.items.indexed.map(
                    (indexedPost) {
                      final index = indexedPost.$1;
                      final post = indexedPost.$2;
                      return Column(
                        children: [
                          if (index > 0) const Divider(height: 1),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.image_outlined),
                            title: Text(
                              post.cat.name ?? strings.unnamedCat,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              post.description?.trim().isNotEmpty == true
                                  ? post.description!.trim()
                                  : strings.noDescription,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                            isThreeLine: true,
                            onTap: () => context.push('/posts/${post.id}'),
                          ),
                        ],
                      );
                    },
                  ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => AppStatePanel(
          icon: Icons.error_outline,
          title: strings.profile,
          message: strings.couldNotLoadProfile,
          action: FilledButton(
            onPressed: () => ref.invalidate(publicProfileProvider(userId)),
            child: Text(strings.retry),
          ),
        ),
      ),
    );
  }

  Future<void> _blockProfile(String profileId, AppStrings strings) async {
    final confirmed = await _confirmBlock(context, strings);
    if (!confirmed || !mounted) {
      return;
    }
    setState(() => _isBlocking = true);
    try {
      await ref.read(mushukistanApiProvider).blockUser(profileId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.userBlocked)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.couldNotLoadSection)),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isBlocking = false);
      }
    }
  }
}

Future<bool> _confirmBlock(BuildContext context, AppStrings strings) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(strings.blockUserTitle),
      content: Text(strings.blockUserMessage),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(strings.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(strings.block),
        ),
      ],
    ),
  );
  return result ?? false;
}

String _initials(String? name) {
  final source = (name ?? 'MU').trim();
  final parts = source.split(RegExp(r'\s+')).where((part) => part.isNotEmpty);
  final initials = parts.take(2).map((part) => part[0]).join();
  return initials.isEmpty ? 'MU' : initials.toUpperCase();
}
