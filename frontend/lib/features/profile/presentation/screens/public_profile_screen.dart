import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/network/api_error.dart';
import '../../../../core/network/mushukistan_api.dart';

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
            return Center(child: Text(strings.profileNotFound));
          }
          final profile = result.profile;
          final posts = result.posts;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
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
                          const SizedBox(width: 16),
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
                                const SizedBox(height: 4),
                                Text(
                                  '${profile.observationCount} ${strings.observations}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  ActionChip(
                    avatar: _isBlocking
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.block_outlined),
                    label: Text(strings.blockUser),
                    onPressed: _isBlocking
                        ? null
                        : () async {
                            final confirmed =
                                await _confirmBlock(context, strings);
                            if (!confirmed || !context.mounted) {
                              return;
                            }
                            setState(() {
                              _isBlocking = true;
                            });
                            try {
                              await ref
                                  .read(mushukistanApiProvider)
                                  .blockUser(profile.id);
                              if (!context.mounted) {
                                return;
                              }
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(strings.userBlocked)),
                              );
                            } finally {
                              if (mounted) {
                                setState(() {
                                  _isBlocking = false;
                                });
                              }
                            }
                          },
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.pets_outlined),
                    label: Text(strings.userObservations),
                    onPressed: profile.allowPublicActivityView
                        ? () =>
                            context.push('/users/${profile.id}/observations')
                        : null,
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.chat_bubble_outline),
                    label: Text(strings.userComments),
                    onPressed: profile.allowPublicActivityView
                        ? () => context.push('/users/${profile.id}/comments')
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (!profile.allowPublicActivityView)
                Text(strings.noActivityVisible)
              else if (posts.items.isEmpty)
                Text(strings.noObservationsYet)
              else
                ...posts.items.map(
                  (post) => Card(
                    child: ListTile(
                      leading: const Icon(Icons.pets_outlined),
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
                  ),
                ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(child: Text(error.toString())),
      ),
    );
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
