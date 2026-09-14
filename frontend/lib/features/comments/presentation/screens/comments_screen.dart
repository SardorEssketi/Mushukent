import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/network/mushukistan_api.dart';
import '../../../../core/widgets/app_surface.dart';

final commentsProvider = FutureProvider.autoDispose
    .family<ApiPage<CommentData>, String>((ref, postId) async {
  return ref.watch(mushukistanApiProvider).listComments(postId);
});

final lostPetCommentsProvider = FutureProvider.autoDispose
    .family<ApiPage<CommentData>, String>((ref, lostPetId) async {
  return ref.watch(mushukistanApiProvider).listLostPetComments(lostPetId);
});

final adoptionPostCommentsProvider = FutureProvider.autoDispose
    .family<ApiPage<CommentData>, String>((ref, adoptionPostId) async {
  return ref
      .watch(mushukistanApiProvider)
      .listAdoptionPostComments(adoptionPostId);
});

class PostCommentsSection extends ConsumerStatefulWidget {
  const PostCommentsSection({
    super.key,
    required this.postId,
    this.padding = const EdgeInsets.all(24),
    this.showCardChrome = false,
  });

  final String postId;
  final EdgeInsetsGeometry padding;
  final bool showCardChrome;

  @override
  ConsumerState<PostCommentsSection> createState() =>
      _PostCommentsSectionState();
}

class LostPetCommentsSection extends ConsumerStatefulWidget {
  const LostPetCommentsSection({
    super.key,
    required this.lostPetId,
    this.padding = const EdgeInsets.all(24),
    this.showCardChrome = false,
  });

  final String lostPetId;
  final EdgeInsetsGeometry padding;
  final bool showCardChrome;

  @override
  ConsumerState<LostPetCommentsSection> createState() =>
      _LostPetCommentsSectionState();
}

class AdoptionPostCommentsSection extends ConsumerStatefulWidget {
  const AdoptionPostCommentsSection({
    super.key,
    required this.adoptionPostId,
    this.padding = const EdgeInsets.all(24),
    this.showCardChrome = false,
  });

  final String adoptionPostId;
  final EdgeInsetsGeometry padding;
  final bool showCardChrome;

  @override
  ConsumerState<AdoptionPostCommentsSection> createState() =>
      _AdoptionPostCommentsSectionState();
}

class _PostCommentsSectionState extends ConsumerState<PostCommentsSection> {
  final _controller = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final commentsAsync = ref.watch(commentsProvider(widget.postId));
    final strings = ref.watch(appStringsProvider);
    return _CommentsContent(
      commentsAsync: commentsAsync,
      strings: strings,
      padding: widget.padding,
      showCardChrome: widget.showCardChrome,
      onSubmit: (content, parentCommentId) => ref
          .read(mushukistanApiProvider)
          .createComment(widget.postId, content, parentCommentId: parentCommentId),
      onRefresh: () => ref.invalidate(commentsProvider(widget.postId)),
      controller: _controller,
      submitting: _submitting,
      error: _error,
      setSubmitting: (value) => setState(() => _submitting = value),
      setError: (value) => setState(() => _error = value),
    );
  }
}

class _LostPetCommentsSectionState
    extends ConsumerState<LostPetCommentsSection> {
  final _controller = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final commentsAsync = ref.watch(lostPetCommentsProvider(widget.lostPetId));
    final strings = ref.watch(appStringsProvider);
    return _CommentsContent(
      commentsAsync: commentsAsync,
      strings: strings,
      padding: widget.padding,
      showCardChrome: widget.showCardChrome,
      onSubmit: (content, parentCommentId) => ref
          .read(mushukistanApiProvider)
          .createLostPetComment(
            widget.lostPetId,
            content,
            parentCommentId: parentCommentId,
          ),
      onRefresh: () =>
          ref.invalidate(lostPetCommentsProvider(widget.lostPetId)),
      controller: _controller,
      submitting: _submitting,
      error: _error,
      setSubmitting: (value) => setState(() => _submitting = value),
      setError: (value) => setState(() => _error = value),
    );
  }
}

class _AdoptionPostCommentsSectionState
    extends ConsumerState<AdoptionPostCommentsSection> {
  final _controller = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final commentsAsync =
        ref.watch(adoptionPostCommentsProvider(widget.adoptionPostId));
    final strings = ref.watch(appStringsProvider);
    return _CommentsContent(
      commentsAsync: commentsAsync,
      strings: strings,
      padding: widget.padding,
      showCardChrome: widget.showCardChrome,
      onSubmit: (content, parentCommentId) => ref
          .read(mushukistanApiProvider)
          .createAdoptionPostComment(
            widget.adoptionPostId,
            content,
            parentCommentId: parentCommentId,
          ),
      onRefresh: () =>
          ref.invalidate(adoptionPostCommentsProvider(widget.adoptionPostId)),
      controller: _controller,
      submitting: _submitting,
      error: _error,
      setSubmitting: (value) => setState(() => _submitting = value),
      setError: (value) => setState(() => _error = value),
    );
  }
}

class _CommentsContent extends StatefulWidget {
  const _CommentsContent({
    required this.commentsAsync,
    required this.strings,
    required this.padding,
    required this.showCardChrome,
    required this.onSubmit,
    required this.onRefresh,
    required this.controller,
    required this.submitting,
    required this.error,
    required this.setSubmitting,
    required this.setError,
  });

  final AsyncValue<ApiPage<CommentData>> commentsAsync;
  final AppStrings strings;
  final EdgeInsetsGeometry padding;
  final bool showCardChrome;
  final Future<void> Function(String content, String? parentCommentId) onSubmit;
  final VoidCallback onRefresh;
  final TextEditingController controller;
  final bool submitting;
  final String? error;
  final ValueChanged<bool> setSubmitting;
  final ValueChanged<String?> setError;

  @override
  State<_CommentsContent> createState() => _CommentsContentState();
}

class _CommentsContentState extends State<_CommentsContent> {
  CommentData? _replyingTo;

  Future<void> _submit() async {
    final content = widget.controller.text.trim();
    if (content.isEmpty || widget.submitting) {
      return;
    }

    final parentCommentId = _replyingTo?.id;
    widget.setSubmitting(true);
    widget.setError(null);
    try {
      await widget.onSubmit(content, parentCommentId);
      widget.controller.clear();
      widget.onRefresh();
      if (mounted) {
        setState(() {
          _replyingTo = null;
        });
      }
    } catch (error) {
      widget.setError(error.toString());
    } finally {
      widget.setSubmitting(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.commentsAsync.when(
      data: (page) {
        final roots = _buildCommentTree(page.items);
        final content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.forum_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  widget.strings.comments,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                Text(
                  '${page.items.length}',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_replyingTo != null)
                      Row(
                        children: [
                          Icon(
                            Icons.reply,
                            size: 18,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '${widget.strings.replyingTo} ${_replyingTo!.user?.name ?? widget.strings.anonymous}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                          ),
                          IconButton(
                            tooltip: widget.strings.cancelReply,
                            onPressed: () {
                              setState(() {
                                _replyingTo = null;
                              });
                            },
                            icon: const Icon(Icons.close, size: 18),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                    TextField(
                      controller: widget.controller,
                      minLines: 1,
                      maxLines: 5,
                      maxLength: 1000,
                      decoration: InputDecoration(
                        hintText: widget.strings.addComment,
                        border: InputBorder.none,
                        counterText: '',
                        suffixIcon: widget.submitting
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : IconButton(
                                tooltip: widget.strings.postComment,
                                onPressed: _submit,
                                icon: const Icon(Icons.send_rounded),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (widget.error != null) ...[
              const SizedBox(height: 12),
              Text(
                widget.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 24),
            if (page.items.isEmpty)
              AppStatePanel(
                icon: Icons.chat_bubble_outline,
                title: widget.strings.noCommentsYet,
              )
            else
              ...roots.map(
                (root) => _CommentThread(
                  node: root,
                  depth: 0,
                  strings: widget.strings,
                  onReply: (comment) {
                    setState(() {
                      _replyingTo = comment;
                    });
                  },
                ),
              ),
          ],
        );

        if (!widget.showCardChrome) {
          return Padding(
            padding: widget.padding,
            child: content,
          );
        }

        return Padding(
          padding: widget.padding,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: content,
            ),
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => Center(child: Text(error.toString())),
    );
  }
}

class _CommentThread extends StatelessWidget {
  const _CommentThread({
    required this.node,
    required this.depth,
    required this.strings,
    required this.onReply,
  });

  final _CommentTreeNode node;
  final int depth;
  final AppStrings strings;
  final ValueChanged<CommentData> onReply;

  @override
  Widget build(BuildContext context) {
    final indentation = ((depth * 16).clamp(0, 96)).toDouble();
    return Padding(
      padding: EdgeInsets.only(left: indentation, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CommentBubble(
            comment: node.comment,
            strings: strings,
            onReply: () => onReply(node.comment),
          ),
          ...node.children.map(
            (child) => _CommentThread(
              node: child,
              depth: depth + 1,
              strings: strings,
              onReply: onReply,
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentBubble extends StatelessWidget {
  const _CommentBubble({
    required this.comment,
    required this.strings,
    required this.onReply,
  });

  final CommentData comment;
  final AppStrings strings;
  final VoidCallback onReply;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final userId = comment.user?.id;
    final userName = comment.user?.name ?? strings.anonymous;
    final avatarUrl = comment.user?.avatarUrl;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outlineVariant),
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 18,
                backgroundImage:
                    avatarUrl == null ? null : NetworkImage(avatarUrl),
                child: avatarUrl == null ? Text(_avatarInitial(userName)) : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: userId == null
                      ? null
                      : () => context.push('/users/$userId'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          userName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _formatDate(comment.createdAt),
                          softWrap: true,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: strings.report,
                onPressed: () => context.push(
                  '/report?type=comment&id=${comment.id}',
                ),
                icon: const Icon(Icons.flag_outlined, size: 20),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 46, top: 8),
            child: Text(comment.content, softWrap: true),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 38, top: 2),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onReply,
                icon: const Icon(Icons.reply, size: 17),
                label: Text(strings.reply),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentTreeNode {
  _CommentTreeNode(this.comment);

  final CommentData comment;
  final List<_CommentTreeNode> children = [];
}

List<_CommentTreeNode> _buildCommentTree(List<CommentData> comments) {
  final nodes = <String, _CommentTreeNode>{
    for (final comment in comments) comment.id: _CommentTreeNode(comment),
  };
  final roots = <_CommentTreeNode>[];
  for (final comment in comments) {
    final node = nodes[comment.id]!;
    final parent = comment.parentCommentId == null
        ? null
        : nodes[comment.parentCommentId!];
    if (parent == null || identical(parent, node)) {
      roots.add(node);
    } else {
      parent.children.add(node);
    }
  }
  return roots;
}

String _avatarInitial(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return '?';
  }
  return trimmed.substring(0, 1).toUpperCase();
}

String _formatDate(DateTime dateTime) {
  final local = dateTime.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
}
