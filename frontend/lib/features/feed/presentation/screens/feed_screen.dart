import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/network/api_error.dart';
import '../../../../core/network/mushukistan_api.dart';
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
      body: Column(
        children: [
          _FeedFilterBar(
            selectedMode: feedMode,
            strings: strings,
            onSelected: (value) {
              ref.read(feedModeProvider.notifier).state = value;
              ref.invalidate(feedPostsProvider);
            },
          ),
          if (feedMode == 'popular')
            _PopularPeriodBar(
              selectedPeriod: popularPeriod,
              strings: strings,
              onSelected: (value) {
                ref.read(feedPopularPeriodProvider.notifier).state = value;
                ref.invalidate(feedPostsProvider);
              },
            ),
          Expanded(
            child: postsAsync.when(
              data: (page) {
                if (page.items.isEmpty) {
                  return _EmptyFeed(strings: strings);
                }
                return RefreshIndicator(
                  onRefresh: () async {
                    final refreshedPosts =
                        ref.refresh(feedPostsProvider.future);
                    await refreshedPosts;
                  },
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: ListView.separated(
                        padding: const EdgeInsets.only(bottom: 12),
                        itemCount: page.items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = page.items[index];
                          return switch (item) {
                            LostPetData() => _LostPetCard(
                                lostPet: item,
                                strings: strings,
                              ),
                            AdoptionPostData() => _AdoptionPostCard(
                                adoptionPost: item,
                                strings: strings,
                              ),
                            PostSummary() => FeedPostCard(
                                post: item,
                                onTap: () => context.push('/posts/${item.id}'),
                              ),
                          };
                        },
                      ),
                    ),
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) => _ErrorPanel(
                message: error.toString(),
                retryLabel: strings.retry,
                onRetry: () => ref.invalidate(feedPostsProvider),
              ),
            ),
          ),
        ],
      ),
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

    return Material(
      color: colorScheme.surface,
      child: InkWell(
        onTap: () => context.push('/lost-pets/${lostPet.id}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
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

    return Material(
      color: colorScheme.surface,
      child: InkWell(
        onTap: () => context.push('/adoption-posts/${adoptionPost.id}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
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

    return Material(
      color: colorScheme.surface,
      child: InkWell(
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(strings.noObservationsYet),
      ),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: Text(retryLabel)),
          ],
        ),
      ),
    );
  }
}

String _formatDate(DateTime dateTime) {
  final local = dateTime.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}
