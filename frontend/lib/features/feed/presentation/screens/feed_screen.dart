import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/network/api_error.dart';
import '../../../../core/network/mushukistan_api.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../../leaderboards/presentation/screens/leaderboard_screen.dart';
import '../../../profile/presentation/screens/profile_screen.dart';

final feedModeProvider = StateProvider<String>((ref) => 'recent');
final feedPopularPeriodProvider = StateProvider<String>((ref) => 'day');

final feedPostsProvider =
    FutureProvider.autoDispose<ApiPage<FeedItem>>((ref) async {
  final api = ref.watch(mushukistanApiProvider);
  final mode = ref.watch(feedModeProvider);
  final popularPeriod = ref.watch(feedPopularPeriodProvider);
  if (mode == 'lost_pets') {
    return api.listLostPets(limit: 30);
  }
  if (mode == 'adoption') {
    return api.listAdoptionPosts(limit: 30);
  }
  return api.listFeed(
    filter: mode,
    popularPeriod: mode == 'popular' ? popularPeriod : null,
    limit: 30,
  );
});

class FeedScreen extends ConsumerWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedMode = ref.watch(feedModeProvider);
    final popularPeriod = ref.watch(feedPopularPeriodProvider);
    final postsAsync = ref.watch(feedPostsProvider);
    final strings = ref.watch(appStringsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mushukistan'),
        actions: [
          if (kIsWeb)
            IconButton(
              tooltip: strings.refresh,
              onPressed: () async {
                final refreshedPosts = ref.refresh(feedPostsProvider.future);
                await refreshedPosts;
              },
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          final refreshedPosts = ref.refresh(feedPostsProvider.future);
          await refreshedPosts;
        },
        child: AppContentWidth(
          maxWidth: AppWidths.wide,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              _HomeHeader(
                onLostPetsTap: () {
                  ref.read(feedModeProvider.notifier).state = 'lost_pets';
                  ref.invalidate(feedPostsProvider);
                },
                onAdoptionTap: () {
                  ref.read(feedModeProvider.notifier).state = 'adoption';
                  ref.invalidate(feedPostsProvider);
                },
                onPlacesTap: () => context.go('/map'),
                onMapTap: () => context.go('/map'),
              ),
              const SizedBox(height: AppSpacing.lg),
              _SectionHeader(
                title: _sectionTitle(feedMode),
                subtitle: _sectionSubtitle(feedMode),
              ),
              const SizedBox(height: AppSpacing.md),
              _FeedFilterBar(
                selectedMode: feedMode,
                strings: strings,
                onSelected: (value) {
                  ref.read(feedModeProvider.notifier).state = value;
                  ref.invalidate(feedPostsProvider);
                },
              ),
              if (feedMode == 'popular') ...[
                const SizedBox(height: AppSpacing.sm),
                _PopularPeriodBar(
                  selectedPeriod: popularPeriod,
                  strings: strings,
                  onSelected: (value) {
                    ref.read(feedPopularPeriodProvider.notifier).state = value;
                    ref.invalidate(feedPostsProvider);
                  },
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              postsAsync.when(
                data: (page) {
                  if (page.items.isEmpty) {
                    return _EmptyFeed(strings: strings);
                  }
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final useGrid = constraints.maxWidth >= 900;
                      if (useGrid) {
                        return GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: AppSpacing.md,
                            crossAxisSpacing: AppSpacing.md,
                            childAspectRatio: 0.78,
                          ),
                          itemCount: page.items.length,
                          itemBuilder: (context, index) => _FeedItemCard(
                            item: page.items[index],
                            strings: strings,
                          ),
                        );
                      }
                      return ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: page.items.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: AppSpacing.md),
                        itemBuilder: (context, index) => _FeedItemCard(
                          item: page.items[index],
                          strings: strings,
                        ),
                      );
                    },
                  );
                },
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 64),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, stackTrace) => _ErrorPanel(
                  message: error.toString(),
                  retryLabel: strings.retry,
                  onRetry: () => ref.invalidate(feedPostsProvider),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({
    required this.onLostPetsTap,
    required this.onAdoptionTap,
    required this.onPlacesTap,
    required this.onMapTap,
  });

  final VoidCallback onLostPetsTap;
  final VoidCallback onAdoptionTap;
  final VoidCallback onPlacesTap;
  final VoidCallback onMapTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return AppCard(
      color: colors.surfaceContainerLow,
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppBadge(
            label: 'The land of cats',
            icon: Icons.public_outlined,
            color: colors.primary,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Everything cats in one calm place',
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Find help, share sightings, search for lost pets, rehome cats, and discover useful places nearby.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 680;
              final actions = [
                _QuickActionCard(
                  icon: Icons.search_outlined,
                  title: 'Lost pets',
                  subtitle: 'Urgent alerts',
                  color: AppPalette.lost,
                  onTap: onLostPetsTap,
                ),
                _QuickActionCard(
                  icon: Icons.home_outlined,
                  title: 'New homes',
                  subtitle: 'Adoption posts',
                  color: AppPalette.adoption,
                  onTap: onAdoptionTap,
                ),
                _QuickActionCard(
                  icon: Icons.local_hospital_outlined,
                  title: 'Useful places',
                  subtitle: 'Vets, shops, shelters',
                  color: colors.secondary,
                  onTap: onPlacesTap,
                ),
                _QuickActionCard(
                  icon: Icons.map_outlined,
                  title: 'Nearby map',
                  subtitle: 'Cats and services',
                  color: colors.primary,
                  onTap: onMapTap,
                ),
              ];
              if (wide) {
                return Row(
                  children: [
                    for (final action in actions) ...[
                      Expanded(child: action),
                      if (action != actions.last)
                        const SizedBox(width: AppSpacing.sm),
                    ],
                  ],
                );
              }
              return Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: actions[0]),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(child: actions[1]),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(child: actions[2]),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(child: actions[3]),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(height: AppSpacing.sm),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _FeedItemCard extends StatelessWidget {
  const _FeedItemCard({required this.item, required this.strings});

  final FeedItem item;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final feedItem = item;
    if (feedItem is LostPetData) {
      return _LostPetCard(lostPet: feedItem, strings: strings);
    }
    if (feedItem is AdoptionPostData) {
      return _AdoptionPostCard(adoptionPost: feedItem, strings: strings);
    }
    final post = feedItem as PostSummary;
    return FeedPostCard(
      post: post,
      onTap: () => context.push('/posts/${post.id}'),
    );
  }
}

String _sectionTitle(String mode) {
  return switch (mode) {
    'lost_pets' => 'Lost pets',
    'adoption' => 'Looking for a home',
    'needs_help' => 'Cats that may need help',
    'popular' => 'Popular in the community',
    _ => 'Latest from Mushukistan',
  };
}

String _sectionSubtitle(String mode) {
  return switch (mode) {
    'lost_pets' =>
      'Recognizable alerts with owner contact and last-seen areas.',
    'adoption' => 'Separate rehoming posts for cats who need a good home.',
    'needs_help' => 'Community observations that may need volunteer attention.',
    'popular' => 'Posts people are responding to most.',
    _ => 'Recent sightings, stories, and updates from people helping cats.',
  };
}

class _FeedFilterBar extends StatelessWidget {
  const _FeedFilterBar({
    required this.selectedMode,
    required this.strings,
    required this.onSelected,
  });

  final String selectedMode;
  final AppStrings strings;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surface,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: SegmentedButton<String>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
              value: 'recent',
              icon: const Icon(Icons.schedule_outlined),
              label: Text(strings.recent),
            ),
            ButtonSegment(
              value: 'popular',
              icon: const Icon(Icons.favorite_outline),
              label: Text(strings.popular),
            ),
            ButtonSegment(
              value: 'needs_help',
              icon: const Icon(Icons.volunteer_activism_outlined),
              label: Text(strings.needsHelp),
            ),
            ButtonSegment(
              value: 'lost_pets',
              icon: const Icon(Icons.search_outlined),
              label: Text(strings.lostPets),
            ),
            const ButtonSegment(
              value: 'adoption',
              icon: Icon(Icons.home_outlined),
              label: Text('Adoption'),
            ),
          ],
          selected: {selectedMode},
          onSelectionChanged: (selection) => onSelected(selection.first),
        ),
      ),
    );
  }
}

class _PopularPeriodBar extends StatelessWidget {
  const _PopularPeriodBar({
    required this.selectedPeriod,
    required this.strings,
    required this.onSelected,
  });

  final String selectedPeriod;
  final AppStrings strings;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surface,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: SegmentedButton<String>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: 'day', label: Text(strings.today)),
            ButtonSegment(value: 'month', label: Text(strings.month)),
            ButtonSegment(value: 'all', label: Text(strings.allTime)),
          ],
          selected: {selectedPeriod},
          onSelectionChanged: (selection) => onSelected(selection.first),
        ),
      ),
    );
  }
}

class _LostPetCard extends StatelessWidget {
  const _LostPetCard({required this.lostPet, required this.strings});

  final LostPetData lostPet;
  final AppStrings strings;

  void _openMap(BuildContext context) {
    final location = lostPet.lastSeenLocation;
    context.go(
      '/map?lat=${location.latitude}&lon=${location.longitude}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final author = lostPet.author;
    final authorId = author?.id;
    final authorName = lostPet.author?.name ?? strings.anonymous;
    final info = lostPet.additionalInfo?.trim();
    final authorProfileTap =
        authorId == null ? null : () => context.push('/users/$authorId');

    return AppCard(
      padding: EdgeInsets.zero,
      onTap: () => context.push('/lost-pets/${lostPet.id}'),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: colorScheme.error, width: 4),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: authorProfileTap,
                      child: CircleAvatar(
                        radius: 18,
                        backgroundColor: colorScheme.primaryContainer,
                        backgroundImage: author?.avatarUrl == null
                            ? null
                            : NetworkImage(author!.avatarUrl!),
                        child: author?.avatarUrl == null
                            ? Text(
                                _avatarInitial(authorName),
                                style: TextStyle(
                                  color: colorScheme.onPrimaryContainer,
                                  fontWeight: FontWeight.w700,
                                ),
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _AuthorInline(
                              authorName: authorName, onTap: authorProfileTap),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: strings.openPost,
                      onPressed: () => context.push('/lost-pets/${lostPet.id}'),
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _FeedMediaPreview(
                imageUrl: lostPet.thumbUrl ?? lostPet.photoUrl,
                imageUrls: lostPet.photoUrls,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _CatNameLine(
                      label: strings.catNameLabel,
                      name: lostPet.petName,
                      trailing: _LostPetBadge(label: strings.lostPet),
                    ),
                    if (info != null && info.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      _LabeledBodyText(
                        label: strings.descriptionLabel,
                        text: info,
                        maxLines: 3,
                      ),
                      const SizedBox(height: 10),
                    ] else
                      const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () => _openMap(context),
                      icon: const Icon(Icons.map_outlined),
                      label: Text(strings.viewOnMap),
                    ),
                    const SizedBox(height: 4),
                    _IconCountAction(
                      tooltip: strings.comments,
                      icon: Icons.chat_bubble_outline,
                      count: lostPet.commentCount,
                      onPressed: () => context.push('/lost-pets/${lostPet.id}'),
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
}

class _AdoptionPostCard extends StatelessWidget {
  const _AdoptionPostCard({
    required this.adoptionPost,
    required this.strings,
  });

  final AdoptionPostData adoptionPost;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final author = adoptionPost.author;
    final authorId = author?.id;
    final authorName = adoptionPost.author?.name ?? strings.anonymous;
    final info = adoptionPost.additionalInfo?.trim();
    final authorProfileTap =
        authorId == null ? null : () => context.push('/users/$authorId');

    return AppCard(
      padding: EdgeInsets.zero,
      onTap: () => context.push('/adoption-posts/${adoptionPost.id}'),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(
            left: BorderSide(color: AppPalette.adoption, width: 4),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: authorProfileTap,
                      child: CircleAvatar(
                        radius: 18,
                        backgroundColor: colorScheme.primaryContainer,
                        backgroundImage: author?.avatarUrl == null
                            ? null
                            : NetworkImage(author!.avatarUrl!),
                        child: author?.avatarUrl == null
                            ? Text(
                                _avatarInitial(authorName),
                                style: TextStyle(
                                  color: colorScheme.onPrimaryContainer,
                                  fontWeight: FontWeight.w700,
                                ),
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _AuthorInline(
                            authorName: authorName,
                            onTap: authorProfileTap,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: strings.openPost,
                      onPressed: () =>
                          context.push('/adoption-posts/${adoptionPost.id}'),
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _FeedMediaPreview(
                imageUrl: adoptionPost.thumbUrl ?? adoptionPost.photoUrl,
                imageUrls: adoptionPost.photoUrls,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _CatNameLine(
                      label: strings.catNameLabel,
                      name: adoptionPost.petName,
                      trailing: const _AdoptionBadge(label: 'Adoption'),
                    ),
                    if (info != null && info.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      _LabeledBodyText(
                        label: strings.descriptionLabel,
                        text: info,
                        maxLines: 3,
                      ),
                      const SizedBox(height: 10),
                    ] else
                      const SizedBox(height: 10),
                    _IconCountAction(
                      tooltip: strings.comments,
                      icon: Icons.chat_bubble_outline,
                      count: adoptionPost.commentCount,
                      onPressed: () =>
                          context.push('/adoption-posts/${adoptionPost.id}'),
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
}

class _AdoptionBadge extends StatelessWidget {
  const _AdoptionBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.home_outlined,
                size: 15, color: colorScheme.onTertiaryContainer),
            const SizedBox(width: 5),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colorScheme.onTertiaryContainer,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LostPetBadge extends StatelessWidget {
  const _LostPetBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colorScheme.error.withValues(alpha: 0.32)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search, size: 15, color: colorScheme.onErrorContainer),
            const SizedBox(width: 5),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colorScheme.onErrorContainer,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageUnavailable extends StatelessWidget {
  const _ImageUnavailable();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      color: colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(
        Icons.image_not_supported_outlined,
        color: colorScheme.onSurfaceVariant,
        size: 40,
      ),
    );
  }
}

class _CatNameLine extends StatelessWidget {
  const _CatNameLine({
    required this.label,
    required this.name,
    this.trailing,
  });

  final String label;
  final String name;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        RichText(
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          text: TextSpan(
            style: Theme.of(context).textTheme.bodyMedium,
            children: [
              TextSpan(
                text: '$label: ',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              TextSpan(text: name),
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _LabeledBodyText extends StatelessWidget {
  const _LabeledBodyText({
    required this.label,
    required this.text,
    this.maxLines,
  });

  final String label;
  final String text;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    return RichText(
      maxLines: maxLines,
      overflow: maxLines == null ? TextOverflow.clip : TextOverflow.ellipsis,
      text: TextSpan(
        style: Theme.of(context).textTheme.bodyMedium,
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          TextSpan(text: text),
        ],
      ),
    );
  }
}

class FeedPostCard extends ConsumerStatefulWidget {
  const FeedPostCard({
    super.key,
    required this.post,
    required this.onTap,
  });

  final PostSummary post;
  final VoidCallback onTap;

  @override
  ConsumerState<FeedPostCard> createState() => _FeedPostCardState();
}

class _FeedPostCardState extends ConsumerState<FeedPostCard> {
  late int _likeCount = widget.post.likeCount;
  bool _liked = false;
  bool _submittingLike = false;

  Future<void> _toggleLike() async {
    if (_submittingLike) {
      return;
    }

    setState(() {
      _submittingLike = true;
    });

    try {
      if (_liked) {
        await ref.read(mushukistanApiProvider).unlikePost(widget.post.id);
        setState(() {
          _liked = false;
          _likeCount = (_likeCount - 1).clamp(0, 1 << 30);
        });
      } else {
        final result =
            await ref.read(mushukistanApiProvider).likePost(widget.post.id);
        setState(() {
          _liked = result.liked;
          _likeCount = result.likeCount;
        });
      }

      ref.invalidate(feedPostsProvider);
      ref.invalidate(profileMeProvider);
      ref.invalidate(leaderboardProvider);
    } on MushukistanApiException catch (error) {
      if (!_liked && error.code == 'ALREADY_LIKED') {
        setState(() {
          _liked = true;
          _likeCount += 1;
        });
      } else {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.userMessage)),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _submittingLike = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final strings = ref.watch(appStringsProvider);
    final author = widget.post.author;
    final authorId = author?.id;
    final authorName = author?.name ?? strings.anonymous;
    final description = widget.post.description?.trim();
    final catName = widget.post.cat.name ?? strings.unnamedCat;
    final statusTag =
        _postStatusLabel(widget.post.status ?? widget.post.cat.status);
    final authorProfileTap =
        authorId == null ? null : () => context.push('/users/$authorId');

    return AppCard(
      padding: EdgeInsets.zero,
      onTap: widget.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: authorProfileTap,
                    child: CircleAvatar(
                      radius: 18,
                      backgroundColor: colorScheme.primaryContainer,
                      backgroundImage: author?.avatarUrl == null
                          ? null
                          : NetworkImage(author!.avatarUrl!),
                      child: author?.avatarUrl == null
                          ? Text(
                              _avatarInitial(authorName),
                              style: TextStyle(
                                color: colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.w700,
                              ),
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _AuthorLine(
                          authorName: authorName,
                          onTap: authorProfileTap,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: strings.openPost,
                    onPressed: widget.onTap,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _FeedMediaPreview(
              imageUrl: widget.post.thumbUrl ?? widget.post.photoUrl,
              imageUrls: widget.post.photoUrls,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
              child: Row(
                children: [
                  _IconCountAction(
                    tooltip: _liked ? strings.unlike : strings.like,
                    icon: _liked ? Icons.favorite : Icons.favorite_outline,
                    count: _likeCount,
                    color: _liked ? colorScheme.error : null,
                    onPressed: _submittingLike ? null : _toggleLike,
                  ),
                  _IconCountAction(
                    tooltip: strings.comments,
                    icon: Icons.chat_bubble_outline,
                    count: widget.post.commentCount,
                    onPressed: widget.onTap,
                  ),
                  const Spacer(),
                  Text(
                    'Published: ${_formatDate(widget.post.createdAt)}',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _CatNameLine(
                    label: strings.catNameLabel,
                    name: catName,
                    trailing: statusTag == null
                        ? null
                        : _StatusBadge(label: statusTag),
                  ),
                  if (description != null && description.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _LabeledBodyText(
                      label: strings.descriptionLabel,
                      text: description,
                    ),
                    const SizedBox(height: 6),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IconCountAction extends StatelessWidget {
  const _IconCountAction({
    required this.tooltip,
    required this.icon,
    required this.count,
    required this.onPressed,
    this.color,
  });

  final String tooltip;
  final IconData icon;
  final int count;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context)
        .textTheme
        .bodyMedium
        ?.copyWith(fontWeight: FontWeight.w700);

    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 4),
              Text(count.toString(), style: style),
            ],
          ),
        ),
      ),
    );
  }
}

class _AuthorLine extends StatelessWidget {
  const _AuthorLine({
    required this.authorName,
    required this.onTap,
  });

  final String authorName;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    final colorScheme = Theme.of(context).colorScheme;
    final child = Text(
      authorName,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: onTap == null
          ? style
          : style?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
    );

    if (onTap == null) {
      return child;
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: child,
        ),
      ),
    );
  }
}

class _AuthorInline extends StatelessWidget {
  const _AuthorInline({
    required this.authorName,
    required this.onTap,
  });

  final String authorName;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.bodySmall;
    final child = Text(
      authorName,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: onTap == null
          ? style
          : style?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
    );

    if (onTap == null) {
      return child;
    }

    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: child,
      ),
    );
  }
}

String _avatarInitial(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return '?';
  }
  return trimmed.substring(0, 1).toUpperCase();
}

double _feedImageAspectRatio(BuildContext context) {
  return MediaQuery.sizeOf(context).width >= 700 ? 4 / 3 : 1;
}

class _FeedMediaPreview extends StatefulWidget {
  const _FeedMediaPreview({
    required this.imageUrl,
    this.imageUrls = const [],
  });

  final String imageUrl;
  final List<String> imageUrls;

  @override
  State<_FeedMediaPreview> createState() => _FeedMediaPreviewState();
}

class _FeedMediaPreviewState extends State<_FeedMediaPreview> {
  late final PageController _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _move(int delta) {
    final urls = _urls;
    if (urls.length <= 1) {
      return;
    }
    final next = (_index + delta).clamp(0, urls.length - 1);
    _controller.animateToPage(
      next,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  List<String> get _urls {
    final urls = widget.imageUrls.where((url) => url.isNotEmpty).toList();
    return urls.isEmpty ? [widget.imageUrl] : urls;
  }

  @override
  Widget build(BuildContext context) {
    final urls = _urls;
    final desktop = MediaQuery.sizeOf(context).width >= 700;
    return AspectRatio(
      aspectRatio: _feedImageAspectRatio(context),
      child: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: urls.length,
            onPageChanged: (value) => setState(() => _index = value),
            itemBuilder: (context, index) {
              return ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Image.network(
                  urls[index],
                  fit: desktop ? BoxFit.contain : BoxFit.cover,
                  width: double.infinity,
                  errorBuilder: (context, error, stackTrace) =>
                      const _ImageUnavailable(),
                ),
              );
            },
          ),
          if (urls.length > 1) ...[
            Positioned(
              top: 12,
              right: 12,
              child: _PhotoCountBadge(count: urls.length),
            ),
            Positioned(
              left: 8,
              top: 0,
              bottom: 0,
              child: _PhotoArrow(
                icon: Icons.chevron_left,
                onPressed: _index == 0 ? null : () => _move(-1),
              ),
            ),
            Positioned(
              right: 8,
              top: 0,
              bottom: 0,
              child: _PhotoArrow(
                icon: Icons.chevron_right,
                onPressed: _index == urls.length - 1 ? null : () => _move(1),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PhotoArrow extends StatelessWidget {
  const _PhotoArrow({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: IconButton.filledTonal(
        visualDensity: VisualDensity.compact,
        onPressed: onPressed,
        icon: Icon(icon),
      ),
    );
  }
}

class _PhotoCountBadge extends StatelessWidget {
  const _PhotoCountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.photo_library_outlined,
              color: Colors.white,
              size: 16,
            ),
            const SizedBox(width: 5),
            Text(
              count.toString(),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.onSecondaryContainer,
                fontWeight: FontWeight.w800,
              ),
        ),
      ),
    );
  }
}

String? _postStatusLabel(String status) {
  return switch (status) {
    'healthy' => 'Healthy',
    'needs_help' => 'Needs help',
    'feed' => 'Feed',
    _ => null,
  };
}

class _EmptyFeed extends StatelessWidget {
  const _EmptyFeed({required this.strings});

  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return AppStatePanel(
      icon: Icons.dynamic_feed_outlined,
      title: strings.noObservationsYet,
      message:
          'Share an observation, lost-pet alert, or rehoming post to help the community start here.',
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({
    required this.message,
    required this.retryLabel,
    required this.onRetry,
  });

  final String message;
  final String retryLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return AppStatePanel(
      icon: Icons.cloud_off_outlined,
      title: 'Could not load this section',
      message: message,
      action: FilledButton(onPressed: onRetry, child: Text(retryLabel)),
    );
  }
}

String _formatDate(DateTime dateTime) {
  final local = dateTime.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}
