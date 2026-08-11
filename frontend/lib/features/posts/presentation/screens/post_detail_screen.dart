import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_error.dart';
import '../../../../core/network/mushukistan_api.dart';
import '../../../comments/presentation/screens/comments_screen.dart';
import '../../../feed/presentation/screens/feed_screen.dart';
import '../../../leaderboards/presentation/screens/leaderboard_screen.dart';
import '../../../profile/presentation/screens/profile_screen.dart';

final postDetailProvider =
    FutureProvider.autoDispose.family<PostDetail, String>((ref, postId) async {
  return ref.watch(mushukistanApiProvider).getPost(postId);
});

class PostDetailScreen extends ConsumerStatefulWidget {
  const PostDetailScreen({super.key, required this.postId});

  final String postId;

  @override
  ConsumerState<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends ConsumerState<PostDetailScreen> {
  bool _submittingLike = false;
  bool? _likedOverride;
  int? _likeCountOverride;

  Future<void> _toggleLike(PostDetail post) async {
    if (_submittingLike) {
      return;
    }

    final isLiked = _likedOverride ?? post.isLikedByMe;
    final currentLikeCount = _likeCountOverride ?? post.likeCount;

    setState(() {
      _submittingLike = true;
    });

    try {
      if (isLiked) {
        await ref.read(mushukistanApiProvider).unlikePost(widget.postId);
        setState(() {
          _likedOverride = false;
          _likeCountOverride = (currentLikeCount - 1).clamp(0, 1 << 30);
        });
      } else {
        final result =
            await ref.read(mushukistanApiProvider).likePost(widget.postId);
        setState(() {
          _likedOverride = result.liked;
          _likeCountOverride = result.likeCount;
        });
      }

      ref.invalidate(postDetailProvider(widget.postId));
      ref.invalidate(feedPostsProvider);
      ref.invalidate(profileMeProvider);
      ref.invalidate(leaderboardProvider);
    } on MushukistanApiException catch (error) {
      if (!isLiked && error.code == 'ALREADY_LIKED') {
        setState(() {
          _likedOverride = true;
          _likeCountOverride = currentLikeCount + 1;
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
    final ref = this.ref;
    final postAsync = ref.watch(postDetailProvider(widget.postId));

    return Scaffold(
      appBar: AppBar(title: const Text('Observation')),
      body: postAsync.when(
        data: (post) {
          final isLiked = _likedOverride ?? post.isLikedByMe;
          final likeCount = _likeCountOverride ?? post.likeCount;
          final author = post.author;
          final authorId = author?.id;
          final authorName = author?.name ?? 'Anonymous';
          final statusTag = _postStatusLabel(post.status ?? post.cat.status);
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _PostDetailGallery(photoUrls: post.photoUrls),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                post.cat.name ?? 'Unnamed cat',
                                style:
                                    Theme.of(context).textTheme.headlineSmall,
                              ),
                              if (statusTag != null)
                                _StatusBadge(label: statusTag),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(post.description?.trim().isNotEmpty == true
                              ? post.description!.trim()
                              : 'No description provided.'),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              _StatCard(
                                  label: 'Likes', value: likeCount.toString()),
                              _StatCard(
                                  label: 'Comments',
                                  value: post.commentCount.toString()),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: _AuthorLink(
                                  authorName: authorName,
                                  onTap: authorId == null
                                      ? null
                                      : () => context.push('/users/$authorId'),
                                ),
                              ),
                              Text(_formatDate(post.createdAt)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: _submittingLike ? null : () => _toggleLike(post),
                    icon: Icon(
                      isLiked ? Icons.favorite : Icons.favorite_outline,
                    ),
                    label: Text(isLiked ? 'Unlike' : 'Like'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () =>
                        context.push('/report?type=post&id=${widget.postId}'),
                    icon: const Icon(Icons.flag_outlined),
                    label: const Text('Report'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              PostCommentsSection(
                  postId: widget.postId, padding: EdgeInsets.zero),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(child: Text(error.toString())),
      ),
    );
  }
}

class _AuthorLink extends StatelessWidget {
  const _AuthorLink({
    required this.authorName,
    required this.onTap,
  });

  final String authorName;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.bodyMedium;
    if (onTap == null) {
      return Text(authorName, style: textStyle);
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            authorName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textStyle?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _PostDetailGallery extends StatefulWidget {
  const _PostDetailGallery({required this.photoUrls});

  final List<String> photoUrls;

  @override
  State<_PostDetailGallery> createState() => _PostDetailGalleryState();
}

class _PostDetailGalleryState extends State<_PostDetailGallery> {
  late final PageController _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _move(int delta) {
    final next = (_index + delta).clamp(0, widget.photoUrls.length - 1);
    _controller.animateToPage(
      next,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final desktop = MediaQuery.sizeOf(context).width >= 700;
    return AspectRatio(
      aspectRatio: desktop ? 4 / 3 : 1.2,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: widget.photoUrls.length,
            onPageChanged: (value) => setState(() => _index = value),
            itemBuilder: (context, index) {
              return ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Image.network(
                  widget.photoUrls[index],
                  fit: desktop ? BoxFit.contain : BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => const Center(
                    child: Icon(Icons.image_not_supported_outlined, size: 48),
                  ),
                ),
              );
            },
          ),
          if (widget.photoUrls.length > 1) ...[
            Positioned(
              left: 8,
              top: 0,
              bottom: 0,
              child: _GalleryArrow(
                icon: Icons.chevron_left,
                onPressed: _index == 0 ? null : () => _move(-1),
              ),
            ),
            Positioned(
              right: 8,
              top: 0,
              bottom: 0,
              child: _GalleryArrow(
                icon: Icons.chevron_right,
                onPressed: _index == widget.photoUrls.length - 1
                    ? null
                    : () => _move(1),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _GalleryArrow extends StatelessWidget {
  const _GalleryArrow({required this.icon, required this.onPressed});

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

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 6),
              Text(value, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatDate(DateTime dateTime) {
  final local = dateTime.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
}
