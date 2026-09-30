import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/network/api_error.dart';
import '../../../../core/network/mushukistan_api.dart';
import '../../../../core/routing/auth_navigation.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../../auth/application/auth_controller.dart';
import '../../../feed/presentation/screens/feed_screen.dart';
import '../widgets/profile_components.dart';

class PublicProfileBundle {
  const PublicProfileBundle({
    required this.profile,
    required this.posts,
    required this.activityAvailable,
  });

  final UserPublicData profile;
  final ApiPage<PostSummary> posts;
  final bool activityAvailable;
}

final publicProfileProvider =
    FutureProvider.autoDispose.family<PublicProfileBundle, String>(
  (ref, userId) async {
    ref.watch(postMutationRevisionProvider);
    final api = ref.watch(mushukistanApiProvider);
    final profile = await api.getPublicProfile(userId);
    if (!profile.allowPublicActivityView) {
      return PublicProfileBundle(
        profile: profile,
        posts: const ApiPage<PostSummary>(items: [], limit: 4),
        activityAvailable: false,
      );
    }
    try {
      final posts = await api.listPublicProfilePosts(userId, limit: 4);
      return PublicProfileBundle(
        profile: profile,
        posts: posts,
        activityAvailable: true,
      );
    } on MushukistanApiException catch (error) {
      if (error.code != 'ACTIVITY_PRIVATE') rethrow;
      return PublicProfileBundle(
        profile: profile,
        posts: const ApiPage<PostSummary>(items: [], limit: 4),
        activityAvailable: false,
      );
    }
  },
);

enum _PublicProfileAction { report, block }

class PublicProfileScreen extends ConsumerStatefulWidget {
  const PublicProfileScreen({super.key, required this.userId});

  final String userId;

  @override
  ConsumerState<PublicProfileScreen> createState() =>
      _PublicProfileScreenState();
}

class _PublicProfileScreenState extends ConsumerState<PublicProfileScreen> {
  bool _isBlocking = false;
  bool _blocked = false;

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(publicProfileProvider(widget.userId));
    final strings = ref.watch(appStringsProvider);
    final profile = profileAsync.valueOrNull?.profile;

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.profile),
        actions: [
          if (profile != null)
            PopupMenuButton<_PublicProfileAction>(
              tooltip: strings.profileActions,
              onSelected: (action) {
                if (action == _PublicProfileAction.report) {
                  context.push(Uri(
                    path: '/report',
                    queryParameters: {
                      'type': 'user',
                      'id': profile.id,
                      'label': profile.name ?? strings.unnamedUser,
                    },
                  ).toString());
                } else {
                  _blockProfile(profile.id, strings);
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: _PublicProfileAction.report,
                  child: Text(strings.report),
                ),
                PopupMenuItem(
                  value: _PublicProfileAction.block,
                  enabled: !_isBlocking && !_blocked,
                  child:
                      Text(_blocked ? strings.userBlocked : strings.blockUser),
                ),
              ],
            ),
        ],
      ),
      body: profileAsync.when(
        skipLoadingOnRefresh: true,
        data: (result) {
          final profile = result.profile;
          final activityAvailable = result.activityAvailable;
          final summary = ProfileSummaryCard(
            name: profile.name ?? strings.unnamedUser,
            strings: strings,
            avatarUrl: profile.avatarUrl,
            bio: profile.bio,
            observationCount: profile.observationCount,
            likesReceived: profile.totalLikesReceived,
            commentCount: profile.commentCount,
            onObservationsTap: activityAvailable
                ? () => context.push('/users/${profile.id}/observations')
                : null,
            onCommentsTap: activityAvailable
                ? () => context.push('/users/${profile.id}/comments')
                : null,
          );
          final recent = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ProfileSectionHeading(
                title: strings.recentObservations,
                action: activityAvailable && result.posts.items.isNotEmpty
                    ? TextButton(
                        onPressed: () =>
                            context.push('/users/${profile.id}/observations'),
                        child: Text(strings.seeAll),
                      )
                    : null,
              ),
              if (!activityAvailable)
                AppCard(
                  child: Row(children: [
                    Icon(Icons.visibility_off_outlined,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: Text(strings.noActivityVisible)),
                  ]),
                )
              else if (result.posts.items.isEmpty)
                AppCard(
                  child: Row(children: [
                    Icon(Icons.pets_outlined,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: Text(strings.noObservationsYet)),
                  ]),
                )
              else
                for (final post in result.posts.items) ...[
                  FeedPostCard(
                    key: ValueKey(post.id),
                    post: post,
                    onTap: () => context.push('/posts/${post.id}'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
            ],
          );
          return AppContentWidth(
            maxWidth: AppWidths.wide,
            child: LayoutBuilder(builder: (context, constraints) {
              final wide = constraints.maxWidth >= AppWidths.readable;
              return ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  if (wide)
                    Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 5, child: summary),
                          const SizedBox(width: AppSpacing.xl),
                          Expanded(flex: 6, child: recent),
                        ])
                  else ...[
                    summary,
                    const SizedBox(height: AppSpacing.xl),
                    recent,
                  ],
                ],
              );
            }),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => AppStatePanel(
          icon:
              error is MushukistanApiException && error.code == 'USER_NOT_FOUND'
                  ? Icons.person_off_outlined
                  : Icons.error_outline,
          title: strings.profile,
          message:
              error is MushukistanApiException && error.code == 'USER_NOT_FOUND'
                  ? strings.profileNotFound
                  : strings.couldNotLoadProfile,
          action:
              error is MushukistanApiException && error.code == 'USER_NOT_FOUND'
                  ? null
                  : FilledButton(
                      onPressed: () =>
                          ref.invalidate(publicProfileProvider(widget.userId)),
                      child: Text(strings.retry),
                    ),
        ),
      ),
    );
  }

  Future<void> _blockProfile(String profileId, AppStrings strings) async {
    if (_isBlocking || _blocked) return;
    if (!ref.read(authControllerProvider).isAuthenticated) {
      requestAuthentication(context);
      return;
    }
    final confirmed = await _confirmBlock(context, strings);
    if (!confirmed || !mounted || _isBlocking || _blocked) return;
    setState(() => _isBlocking = true);
    try {
      await ref.read(mushukistanApiProvider).blockUser(profileId);
      if (mounted) {
        setState(() => _blocked = true);
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
      if (mounted) setState(() => _isBlocking = false);
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
