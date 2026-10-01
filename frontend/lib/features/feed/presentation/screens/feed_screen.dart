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
import '../../../leaderboards/presentation/screens/leaderboard_screen.dart';
import '../../../profile/presentation/screens/profile_screen.dart';
import '../widgets/feed_card_parts.dart';

final feedModeProvider = StateProvider<String>((ref) => 'recent');
final feedPopularPeriodProvider = StateProvider<String>((ref) => 'day');
final postLikeOverridesProvider = StateProvider<Map<String, LikeData>>(
  (ref) => const {},
);

const _pageSize = 30;
const _mobileFeedBreakpoint = 700.0;

String _feedKey(String mode, String period, String? userId) =>
    '$mode:${mode == 'popular' ? period : ''}:${userId ?? 'guest'}';

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

Future<ApiPage<FeedItem>> _fetchFeedPage(
  MushukistanApi api, {
  required String mode,
  required String period,
  required bool includeViewerContext,
  String? cursor,
}) {
  if (mode == 'lost_pets') {
    return api.listLostPets(limit: _pageSize, cursor: cursor);
  }
  if (mode == 'adoption') {
    return api.listAdoptionPosts(limit: _pageSize, cursor: cursor);
  }
  return api.listFeed(
    filter: mode,
    popularPeriod: mode == 'popular' ? period : null,
    limit: _pageSize,
    cursor: cursor,
    includeViewerContext: includeViewerContext,
  );
}

final feedPostsProvider =
    FutureProvider.autoDispose<ApiPage<FeedItem>>((ref) async {
  ref.watch(postMutationRevisionProvider);
  final lostPetOverrides = ref.watch(lostPetMutationOverridesProvider);
  final deletedLostPetIds = ref.watch(deletedLostPetIdsProvider);
  final resolvedLostPetIds = ref.watch(resolvedLostPetIdsProvider);
  final adoptionOverrides = ref.watch(adoptionMutationOverridesProvider);
  final deletedAdoptionIds = ref.watch(deletedAdoptionIdsProvider);
  final resolvedAdoptionIds = ref.watch(resolvedAdoptionIdsProvider);
  final api = ref.watch(mushukistanApiProvider);
  final mode = ref.watch(feedModeProvider);
  final period =
      mode == 'popular' ? ref.watch(feedPopularPeriodProvider) : 'day';
  final includeViewerContext = ref.watch(
    authControllerProvider.select((state) => state.isAuthenticated),
  );
  final page = await _fetchFeedPage(
    api,
    mode: mode,
    period: period,
    includeViewerContext: includeViewerContext,
  );
  return ApiPage<FeedItem>(
    items: _applyPostMutations(
      page.items,
      overrides: lostPetOverrides,
      deletedIds: deletedLostPetIds,
      resolvedIds: resolvedLostPetIds,
      adoptionOverrides: adoptionOverrides,
      deletedAdoptionIds: deletedAdoptionIds,
      resolvedAdoptionIds: resolvedAdoptionIds,
    ),
    nextCursor: page.nextCursor,
    limit: page.limit,
  );
});

List<FeedItem> _applyPostMutations(
  List<FeedItem> items, {
  required Map<String, LostPetData> overrides,
  required Set<String> deletedIds,
  required Set<String> resolvedIds,
  required Map<String, AdoptionPostData> adoptionOverrides,
  required Set<String> deletedAdoptionIds,
  required Set<String> resolvedAdoptionIds,
}) {
  final result = <FeedItem>[];
  for (final item in items) {
    if (item is AdoptionPostData) {
      if (deletedAdoptionIds.contains(item.id) ||
          resolvedAdoptionIds.contains(item.id)) {
        continue;
      }
      final updated = adoptionOverrides[item.id] ?? item;
      if (!updated.isResolved) result.add(updated);
    } else if (item is LostPetData) {
      if (deletedIds.contains(item.id) || resolvedIds.contains(item.id)) {
        continue;
      }
      final updated = overrides[item.id] ?? item;
      if (!updated.isResolved) result.add(updated);
    } else {
      result.add(item);
    }
  }
  return result;
}

List<FeedItem> _deduplicate(List<FeedItem> items) {
  final seen = <String>{};
  return [
    for (final item in items)
      if (seen.add('${item.itemType}:${item.id}')) item,
  ];
}

bool _samePageIdentity(ApiPage<FeedItem>? previous, ApiPage<FeedItem> next) {
  if (previous == null ||
      previous.nextCursor != next.nextCursor ||
      previous.items.length != next.items.length) {
    return false;
  }
  for (var index = 0; index < next.items.length; index++) {
    final before = previous.items[index];
    final after = next.items[index];
    if (before.itemType != after.itemType || before.id != after.id) {
      return false;
    }
  }
  return true;
}

class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  final ScrollController _scrollController = ScrollController();
  String _activeKey = '';
  int _generation = 0;
  ApiPage<FeedItem>? _firstPage;
  ApiPage<FeedItem>? _observedFirstPage;
  final List<FeedItem> _laterItems = [];
  final Set<String> _requestedCursors = {};
  String? _nextCursor;
  bool _loadingMore = false;
  bool _pageError = false;
  bool _replaceOnNextPage = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_checkLoadMore);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _resetForView(String key) {
    _activeKey = key;
    _generation++;
    _firstPage = null;
    _observedFirstPage = null;
    _laterItems.clear();
    _requestedCursors.clear();
    _nextCursor = null;
    _loadingMore = false;
    _pageError = false;
    _replaceOnNextPage = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });
  }

  void _acceptFirstPage(ApiPage<FeedItem> page) {
    if (_replaceOnNextPage || !_samePageIdentity(_firstPage, page)) {
      _laterItems.clear();
      _requestedCursors.clear();
      _nextCursor = page.nextCursor;
      _pageError = false;
    }
    _firstPage = page;
    _observedFirstPage = page;
    _replaceOnNextPage = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _checkLoadMore();
      }
    });
  }

  void _checkLoadMore() {
    if (!_scrollController.hasClients ||
        _scrollController.position.extentAfter >= 700 ||
        _nextCursor == null ||
        _loadingMore ||
        _replaceOnNextPage ||
        _pageError) {
      return;
    }
    _loadMore();
  }

  Future<void> _loadMore() async {
    final cursor = _nextCursor;
    if (cursor == null ||
        _loadingMore ||
        _replaceOnNextPage ||
        _requestedCursors.contains(cursor)) {
      return;
    }
    _requestedCursors.add(cursor);
    final generation = _generation;
    final mode = ref.read(feedModeProvider);
    final period = ref.read(feedPopularPeriodProvider);
    final userId = ref.read(currentUserProvider)?.id;
    final authenticated = userId != null;
    setState(() {
      _loadingMore = true;
      _pageError = false;
    });
    try {
      final page = await _fetchFeedPage(
        ref.read(mushukistanApiProvider),
        mode: mode,
        period: period,
        includeViewerContext: authenticated,
        cursor: cursor,
      );
      if (!mounted ||
          generation != _generation ||
          userId != ref.read(currentUserProvider)?.id) {
        return;
      }
      setState(() {
        _laterItems.addAll(page.items);
        final next = page.nextCursor;
        _nextCursor =
            next == cursor || (next != null && _requestedCursors.contains(next))
                ? null
                : next;
        _loadingMore = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _checkLoadMore();
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      _requestedCursors.remove(cursor);
      setState(() {
        _loadingMore = false;
        _pageError = true;
      });
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _generation++;
      _replaceOnNextPage = true;
      _loadingMore = false;
      _pageError = false;
    });
    try {
      final refreshed = ref.refresh(feedPostsProvider.future);
      await refreshed;
    } catch (_) {
      if (!mounted) return;
      _replaceOnNextPage = false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(ref.read(appStringsProvider).couldNotLoadSection)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(feedModeProvider);
    final period = ref.watch(feedPopularPeriodProvider);
    final userId = ref.watch(currentUserProvider)?.id;
    final authenticated = userId != null;
    final key = _feedKey(mode, period, userId);
    final pageAsync = ref.watch(feedPostsProvider);
    final strings = ref.watch(appStringsProvider);

    if (_activeKey != key) _resetForView(key);
    final received = pageAsync.isLoading ? null : pageAsync.valueOrNull;
    if (received != null && !identical(received, _observedFirstPage)) {
      _acceptFirstPage(received);
    }
    final items = _deduplicate(_applyPostMutations(
      [...?_firstPage?.items, ..._laterItems],
      overrides: ref.watch(lostPetMutationOverridesProvider),
      deletedIds: ref.watch(deletedLostPetIdsProvider),
      resolvedIds: ref.watch(resolvedLostPetIdsProvider),
      adoptionOverrides: ref.watch(adoptionMutationOverridesProvider),
      deletedAdoptionIds: ref.watch(deletedAdoptionIdsProvider),
      resolvedAdoptionIds: ref.watch(resolvedAdoptionIdsProvider),
    ));

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        titleSpacing: 0,
        title: AppContentWidth(
          maxWidth: AppWidths.readable,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Align(
                alignment: Alignment.centerLeft, child: Text(strings.feed)),
          ),
        ),
        actions: [
          if (!authenticated)
            TextButton(
              onPressed: () => context.push('/login'),
              child: Text(strings.login),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: AppContentWidth(
          maxWidth: AppWidths.readable,
          child: CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _FeedFilterBar(
                        selectedMode: mode,
                        strings: strings,
                        onSelected: (value) =>
                            ref.read(feedModeProvider.notifier).state = value,
                      ),
                      if (mode == 'popular') ...[
                        const SizedBox(height: AppSpacing.sm),
                        _PopularPeriodBar(
                          selectedPeriod: period,
                          strings: strings,
                          onSelected: (value) => ref
                              .read(feedPopularPeriodProvider.notifier)
                              .state = value,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (_firstPage == null && pageAsync.isLoading)
                const SliverToBoxAdapter(child: _FeedLoading())
              else if (_firstPage == null && pageAsync.hasError)
                SliverToBoxAdapter(
                  child: AppStatePanel(
                    icon: Icons.error_outline,
                    title: strings.couldNotLoadSection,
                    action: FilledButton(
                      onPressed: () => ref.invalidate(feedPostsProvider),
                      child: Text(strings.retry),
                    ),
                  ),
                )
              else if (items.isEmpty)
                SliverToBoxAdapter(
                  child: AppStatePanel(
                    icon: Icons.dynamic_feed_outlined,
                    title: strings.feedEmptyMessage(mode),
                    message: mode == 'recent' ? strings.emptyFeedMessage : null,
                  ),
                )
              else
                SliverList.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) => Padding(
                    key:
                        ValueKey('${items[index].itemType}:${items[index].id}'),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: _FeedItemCard(item: items[index], strings: strings),
                  ),
                ),
              if (_loadingMore)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.lg),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
              if (_pageError)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    child: Row(children: [
                      Expanded(child: Text(strings.couldNotLoadSection)),
                      TextButton(
                        onPressed: _loadMore,
                        child: Text(strings.retry),
                      ),
                    ]),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeedLoading extends StatelessWidget {
  const _FeedLoading();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(children: [
        for (var i = 0; i < 2; i++) ...[
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(AppRadii.card),
            ),
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  CircleAvatar(backgroundColor: colors.surfaceContainerHigh),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                        height: 12, color: colors.surfaceContainerHigh),
                  ),
                ]),
              ),
              SizedBox(
                height: 170,
                child: ColoredBox(color: colors.surfaceContainerLow),
              ),
              const SizedBox(height: 48),
            ]),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
      ]),
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
    void select(String value) =>
        onSelected(mobile && selectedMode == value ? 'recent' : value);
    return SizedBox(
      height: 48,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          if (!mobile)
            _FilterTab(
              value: 'recent',
              selectedValue: selectedMode,
              label: strings.recent,
              onSelected: select,
            ),
          _FilterTab(
            value: 'popular',
            selectedValue: selectedMode,
            label: strings.popular,
            onSelected: select,
          ),
          _FilterTab(
            value: 'needs_help',
            selectedValue: selectedMode,
            label: strings.needsHelp,
            onSelected: select,
          ),
          _FilterTab(
            value: 'lost_pets',
            selectedValue: selectedMode,
            label: strings.lostPets,
            onSelected: select,
          ),
          _FilterTab(
            value: 'adoption',
            selectedValue: selectedMode,
            label: strings.adoption,
            onSelected: select,
          ),
        ]),
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
        constraints: const BoxConstraints(minWidth: 64, minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
              bottom: BorderSide(
            color: selected ? colors.primary : Colors.transparent,
            width: 2,
          )),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: selected ? colors.primary : colors.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
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
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (final (value, label) in [
          ('day', strings.today),
          ('month', strings.month),
          ('all', strings.allTime),
        ]) ...[
          ChoiceChip(
            label: Text(label),
            selected: selectedPeriod == value,
            showCheckmark: false,
            onSelected: (_) => onSelected(value),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ]),
    );
  }
}

class _FeedItemCard extends StatelessWidget {
  const _FeedItemCard({required this.item, required this.strings});

  final FeedItem item;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    if (item is LostPetData) {
      return _LostPetCard(lostPet: item as LostPetData, strings: strings);
    }
    if (item is AdoptionPostData) {
      return _AdoptionPostCard(
          post: item as AdoptionPostData, strings: strings);
    }
    final post = item as PostSummary;
    return FeedPostCard(
      post: post,
      onTap: () => context.push('/posts/${post.id}'),
    );
  }
}

class _LostPetCard extends StatelessWidget {
  const _LostPetCard({required this.lostPet, required this.strings});

  final LostPetData lostPet;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final info = lostPet.additionalInfo?.trim();
    final authorId = lostPet.author?.id;
    void openPost() => context.push('/lost-pets/${lostPet.id}');
    return FeedCardFrame(
      onTap: openPost,
      accent: colors.error,
      children: [
        FeedAuthorHeader(
          author: lostPet.author,
          createdAt: lostPet.createdAt,
          strings: strings,
          onAuthorTap:
              authorId == null ? null : () => context.push('/users/$authorId'),
        ),
        FeedMedia(
          photoUrl: lostPet.photoUrl,
          thumbUrl: lostPet.thumbUrl,
          photoUrls: lostPet.photoUrls,
          strings: strings,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            FeedPetTitle(
              name: lostPet.petName,
              badge:
                  FeedKindBadge(kind: FeedKind.lostPet, label: strings.lostPet),
            ),
            if (info != null && info.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              FeedBodyText(text: info, strings: strings),
            ],
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 12, 8),
          child: Row(children: [
            FeedCountAction(
              tooltip: strings.comments,
              icon: Icons.chat_bubble_outline,
              count: lostPet.commentCount,
              onPressed: openPost,
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () {
                final location = lostPet.lastSeenLocation;
                context.go(
                    '/map?lat=${location.latitude}&lon=${location.longitude}'
                    '&lostPetId=${lostPet.id}');
              },
              icon: const Icon(Icons.map_outlined, size: 19),
              label: Text(strings.viewOnMap),
            ),
          ]),
        ),
      ],
    );
  }
}

class _AdoptionPostCard extends StatelessWidget {
  const _AdoptionPostCard({required this.post, required this.strings});

  final AdoptionPostData post;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final info = post.additionalInfo?.trim();
    final authorId = post.author?.id;
    void openPost() => context.push('/adoption-posts/${post.id}');
    return FeedCardFrame(
      onTap: openPost,
      accent: colors.tertiary,
      children: [
        FeedAuthorHeader(
          author: post.author,
          createdAt: post.createdAt,
          strings: strings,
          onAuthorTap:
              authorId == null ? null : () => context.push('/users/$authorId'),
        ),
        FeedMedia(
          photoUrl: post.photoUrl,
          thumbUrl: post.thumbUrl,
          photoUrls: post.photoUrls,
          strings: strings,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            FeedPetTitle(
              name: post.petName,
              badge: FeedKindBadge(
                  kind: FeedKind.rehoming, label: strings.adoption),
            ),
            if (info != null && info.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              FeedBodyText(text: info, strings: strings),
            ],
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 12, 8),
          child: FeedCountAction(
            tooltip: strings.comments,
            icon: Icons.chat_bubble_outline,
            count: post.commentCount,
            onPressed: openPost,
          ),
        ),
      ],
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
    if (_submittingLike) return;
    if (!ref.read(authControllerProvider).isAuthenticated) {
      requestAuthentication(context);
      return;
    }
    final current = ref.read(postLikeOverridesProvider)[widget.post.id];
    final wasLiked = current?.liked ?? _liked;
    final oldCount = current?.likeCount ?? _likeCount;
    final newCount = (oldCount + (wasLiked ? -1 : 1)).clamp(0, 1 << 30);
    setState(() {
      _submittingLike = true;
      _liked = !wasLiked;
      _likeCount = newCount;
    });
    setPostLikeOverride(ref, widget.post.id,
        liked: !wasLiked, likeCount: newCount);
    try {
      if (wasLiked) {
        await ref.read(mushukistanApiProvider).unlikePost(widget.post.id);
      } else {
        final result =
            await ref.read(mushukistanApiProvider).likePost(widget.post.id);
        if (!mounted) return;
        setState(() {
          _liked = result.liked;
          _likeCount = result.likeCount;
        });
        setPostLikeOverride(ref, widget.post.id,
            liked: result.liked, likeCount: result.likeCount);
      }
      ref.invalidate(feedPostsProvider);
      ref.invalidate(profileMeProvider);
      ref.invalidate(leaderboardProvider);
    } on MushukistanApiException catch (error) {
      if (!mounted) return;
      if (!wasLiked && error.code == 'ALREADY_LIKED') {
        setState(() {
          _liked = true;
          _likeCount = newCount;
        });
        setPostLikeOverride(ref, widget.post.id,
            liked: true, likeCount: newCount);
      } else {
        _restoreLike(wasLiked, oldCount);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.userMessage)),
        );
      }
    } catch (_) {
      if (!mounted) return;
      _restoreLike(wasLiked, oldCount);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(ref.read(appStringsProvider).couldNotLoadSection)),
      );
    } finally {
      if (mounted) setState(() => _submittingLike = false);
    }
  }

  void _restoreLike(bool liked, int count) {
    setState(() {
      _liked = liked;
      _likeCount = count;
    });
    setPostLikeOverride(ref, widget.post.id, liked: liked, likeCount: count);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final strings = ref.watch(appStringsProvider);
    final override = ref.watch(postLikeOverridesProvider)[widget.post.id];
    final liked = override?.liked ?? _liked;
    final likeCount = override?.likeCount ?? _likeCount;
    final authorId = widget.post.author?.id;
    final description = widget.post.description?.trim();
    final catName = widget.post.cat.name?.trim();
    final needsHelp = widget.post.kind == 'needs_help';
    final hasName = catName != null && catName.isNotEmpty;
    return FeedCardFrame(
      onTap: widget.onTap,
      accent: needsHelp ? colors.tertiary : null,
      children: [
        FeedAuthorHeader(
          author: widget.post.author,
          createdAt: widget.post.createdAt,
          strings: strings,
          onAuthorTap:
              authorId == null ? null : () => context.push('/users/$authorId'),
        ),
        FeedMedia(
          photoUrl: widget.post.photoUrl,
          thumbUrl: widget.post.thumbUrl,
          photoUrls: widget.post.photoUrls,
          strings: strings,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (hasName)
              FeedPetTitle(
                name: catName,
                badge: needsHelp
                    ? FeedKindBadge(
                        kind: FeedKind.needsHelp, label: strings.needsHelp)
                    : null,
              )
            else if (needsHelp)
              FeedKindBadge(kind: FeedKind.needsHelp, label: strings.needsHelp)
            else if (description == null || description.isEmpty)
              Text(strings.unnamedCat,
                  style: Theme.of(context).textTheme.titleMedium),
            if (description != null && description.isNotEmpty) ...[
              if (hasName || needsHelp) const SizedBox(height: AppSpacing.sm),
              FeedBodyText(text: description, strings: strings),
            ],
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 12, 8),
          child: Row(children: [
            FeedCountAction(
              tooltip: liked ? strings.unlike : strings.like,
              icon: liked ? Icons.favorite : Icons.favorite_outline,
              count: likeCount,
              active: liked,
              onPressed: _toggleLike,
            ),
            FeedCountAction(
              tooltip: strings.comments,
              icon: Icons.chat_bubble_outline,
              count: widget.post.commentCount,
              onPressed: widget.onTap,
            ),
          ]),
        ),
      ],
    );
  }
}
