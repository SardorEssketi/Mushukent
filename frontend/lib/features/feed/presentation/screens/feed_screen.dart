import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/localization/language_controller.dart';
import '../../../../core/network/api_error.dart';
import '../../../../core/network/mushukistan_api.dart';
import '../../../../core/routing/auth_navigation.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../../leaderboards/presentation/screens/leaderboard_screen.dart';
import '../../../auth/application/auth_controller.dart';
import '../../../profile/presentation/screens/profile_screen.dart';

final feedModeProvider = StateProvider<String>((ref) => 'recent');
final feedPopularPeriodProvider = StateProvider<String>((ref) => 'day');
final postLikeOverridesProvider = StateProvider<Map<String, LikeData>>(
  (ref) => const {},
);

const _mobileFeedBreakpoint = 700.0;

void setPostLikeOverride(
  WidgetRef ref,
  String postId, {
  required bool liked,
  required int likeCount,
}) {
  ref.read(postLikeOverridesProvider.notifier).state = {
    ...ref.read(postLikeOverridesProvider),
    postId: LikeData(liked: liked, likeCount: likeCount),
  };
}

final feedPostsProvider =
    FutureProvider.autoDispose<ApiPage<FeedItem>>((ref) async {
  ref.watch(postMutationRevisionProvider);
  final api = ref.watch(mushukistanApiProvider);
  final mode = ref.watch(feedModeProvider);
  final popularPeriod = ref.watch(feedPopularPeriodProvider);
  final includeViewerContext = ref.watch(
    authControllerProvider.select((state) => state.isAuthenticated),
  );
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
    includeViewerContext: includeViewerContext,
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
    final isAuthenticated = ref.watch(
      authControllerProvider.select((state) => state.isAuthenticated),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.feed),
        actions: [
          if (!isAuthenticated)
            TextButton(
              onPressed: () => context.push('/login'),
              child: Text(strings.login),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          final refreshedPosts = ref.refresh(feedPostsProvider.future);
          await refreshedPosts;
        },
        child: AppContentWidth(
          maxWidth: AppWidths.compact,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
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
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 64),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, stackTrace) => AppStatePanel(
                  icon: Icons.error_outline,
                  title: strings.couldNotLoadSection,
                  action: FilledButton(
                    onPressed: () => ref.invalidate(feedPostsProvider),
                    child: Text(strings.retry),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
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
    final mobile = MediaQuery.sizeOf(context).width < _mobileFeedBreakpoint;

    void selectMode(String value) {
      onSelected(mobile && selectedMode == value ? 'recent' : value);
    }

    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          if (!mobile)
            _FilterTab(
              value: 'recent',
              selectedValue: selectedMode,
              label: strings.recent,
              onSelected: selectMode,
            ),
          _FilterTab(
            value: 'popular',
            selectedValue: selectedMode,
            label: strings.popular,
            onSelected: selectMode,
          ),
          _FilterTab(
            value: 'needs_help',
            selectedValue: selectedMode,
            label: strings.needsHelp,
            onSelected: selectMode,
          ),
          _FilterTab(
            value: 'lost_pets',
            selectedValue: selectedMode,
            label: strings.lostPets,
            onSelected: selectMode,
          ),
          _FilterTab(
            value: 'adoption',
            selectedValue: selectedMode,
            label: strings.adoption,
            onSelected: selectMode,
          ),
        ],
      ),
    );
  }
}

class _FilterTab extends StatelessWidget {
  const _FilterTab({
    required this.value,
    required this.selectedValue,
    required this.label,
    required this.onSelected,
  });

  final String value;
  final String selectedValue;
  final String label;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final selected = selectedValue == value;
    return InkWell(
      onTap: () => onSelected(value),
      child: Container(
        constraints: const BoxConstraints(minWidth: 64),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? colors.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: selected ? colors.primary : colors.onSurfaceVariant,
              ),
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
    return DropdownButton<String>(
      value: selectedPeriod,
      isExpanded: true,
      items: [
        DropdownMenuItem(value: 'day', child: Text(strings.today)),
        DropdownMenuItem(value: 'month', child: Text(strings.month)),
        DropdownMenuItem(value: 'all', child: Text(strings.allTime)),
      ],
      onChanged: (value) {
        if (value != null) onSelected(value);
      },
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
                      trailing: _AdoptionBadge(label: strings.adoption),
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
        borderRadius: BorderRadius.circular(AppRadii.sm),
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
        borderRadius: BorderRadius.circular(AppRadii.sm),
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$label: ',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                TextSpan(text: name),
              ],
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          trailing!,
        ],
      ],
    );
  }
}

class _LabeledBodyText extends StatefulWidget {
  const _LabeledBodyText({
    required this.label,
    required this.text,
    this.maxLines,
  });

  final String label;
  final String text;
  final int? maxLines;

  @override
  State<_LabeledBodyText> createState() => _LabeledBodyTextState();
}

class _LabeledBodyTextState extends State<_LabeledBodyText> {
  bool _expanded = false;

  TextSpan _textSpan(BuildContext context) {
    return TextSpan(
      style: Theme.of(context).textTheme.bodyMedium,
      children: [
        TextSpan(
          text: '${widget.label}: ',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        TextSpan(text: widget.text),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.forLanguage(
      AppLanguage.fromCode(Localizations.localeOf(context).languageCode),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: _textSpan(context),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: widget.maxLines,
          ellipsis: '…',
        )..layout(maxWidth: constraints.maxWidth);
        final isLong = widget.maxLines != null && painter.didExceedMaxLines;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RichText(
              maxLines: _expanded ? null : widget.maxLines,
              overflow: _expanded ? TextOverflow.clip : TextOverflow.ellipsis,
              textScaler: MediaQuery.textScalerOf(context),
              text: _textSpan(context),
            ),
            if (isLong || _expanded)
              TextButton(
                onPressed: () => setState(() => _expanded = !_expanded),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(_expanded ? strings.showLess : strings.readMore),
              ),
          ],
        );
      },
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
  late bool _liked = widget.post.isLikedByMe;
  bool _submittingLike = false;

  @override
  void didUpdateWidget(covariant FeedPostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post.id != widget.post.id ||
        oldWidget.post.likeCount != widget.post.likeCount ||
        oldWidget.post.isLikedByMe != widget.post.isLikedByMe) {
      _likeCount = widget.post.likeCount;
      _liked = widget.post.isLikedByMe;
    }
  }

  Future<void> _toggleLike() async {
    if (_submittingLike) {
      return;
    }
    if (!ref.read(authControllerProvider).isAuthenticated) {
      requestAuthentication(context);
      return;
    }

    final currentOverride = ref.read(postLikeOverridesProvider)[widget.post.id];
    final currentlyLiked = currentOverride?.liked ?? _liked;
    final currentLikeCount = currentOverride?.likeCount ?? _likeCount;

    setState(() {
      _submittingLike = true;
    });

    try {
      if (currentlyLiked) {
        await ref.read(mushukistanApiProvider).unlikePost(widget.post.id);
        final nextCount = (currentLikeCount - 1).clamp(0, 1 << 30);
        setState(() {
          _liked = false;
          _likeCount = nextCount;
        });
        setPostLikeOverride(
          ref,
          widget.post.id,
          liked: false,
          likeCount: nextCount,
        );
      } else {
        final result =
            await ref.read(mushukistanApiProvider).likePost(widget.post.id);
        setState(() {
          _liked = result.liked;
          _likeCount = result.likeCount;
        });
        setPostLikeOverride(
          ref,
          widget.post.id,
          liked: result.liked,
          likeCount: result.likeCount,
        );
      }

      ref.invalidate(feedPostsProvider);
      ref.invalidate(profileMeProvider);
      ref.invalidate(leaderboardProvider);
    } on MushukistanApiException catch (error) {
      if (!currentlyLiked && error.code == 'ALREADY_LIKED') {
        final nextCount = currentLikeCount + 1;
        setState(() {
          _liked = true;
          _likeCount = nextCount;
        });
        setPostLikeOverride(
          ref,
          widget.post.id,
          liked: true,
          likeCount: nextCount,
        );
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
    final likeOverride = ref.watch(postLikeOverridesProvider)[widget.post.id];
    final isLiked = likeOverride?.liked ?? _liked;
    final likeCount = likeOverride?.likeCount ?? _likeCount;
    final author = widget.post.author;
    final authorId = author?.id;
    final authorName = author?.name ?? strings.anonymous;
    final description = widget.post.description?.trim();
    final catName = widget.post.cat.name ?? strings.unnamedCat;
    final kindBadge =
        widget.post.kind == 'needs_help' ? strings.needsHelp : null;
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      _IconCountAction(
                        tooltip: isLiked ? strings.unlike : strings.like,
                        icon: isLiked ? Icons.favorite : Icons.favorite_outline,
                        count: likeCount,
                        color: isLiked ? colorScheme.error : null,
                        onPressed: _submittingLike ? null : _toggleLike,
                      ),
                      _IconCountAction(
                        tooltip: strings.comments,
                        icon: Icons.chat_bubble_outline,
                        count: widget.post.commentCount,
                        onPressed: widget.onTap,
                      ),
                    ],
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
                    trailing: kindBadge == null
                        ? null
                        : _StatusBadge(label: kindBadge),
                  ),
                  if (description != null && description.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _LabeledBodyText(
                      label: strings.descriptionLabel,
                      text: description,
                      maxLines: 4,
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
  return MediaQuery.sizeOf(context).width >= _mobileFeedBreakpoint ? 4 / 3 : 1;
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
    final desktop = MediaQuery.sizeOf(context).width >= _mobileFeedBreakpoint;
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
        borderRadius: BorderRadius.circular(AppRadii.sm),
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
        borderRadius: BorderRadius.circular(AppRadii.sm),
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

class _EmptyFeed extends StatelessWidget {
  const _EmptyFeed({required this.strings});

  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return AppStatePanel(
      icon: Icons.dynamic_feed_outlined,
      title: strings.noObservationsYet,
      message: strings.emptyFeedMessage,
    );
  }
}
