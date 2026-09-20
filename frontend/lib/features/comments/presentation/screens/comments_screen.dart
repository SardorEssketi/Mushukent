import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/network/api_error.dart';
import '../../../../core/network/mushukistan_api.dart';
import '../../../../core/routing/auth_navigation.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../../auth/application/auth_controller.dart';

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
    this.now,
  });

  final String postId;
  final EdgeInsetsGeometry padding;
  final bool showCardChrome;
  final DateTime? now;

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
    final currentUser = ref.watch(currentUserProvider);
    final isAuthenticated = ref.watch(
      authControllerProvider.select((state) => state.isAuthenticated),
    );
    final api = ref.read(mushukistanApiProvider);
    return _CommentsContent(
      commentsAsync: commentsAsync,
      strings: strings,
      padding: widget.padding,
      showCardChrome: widget.showCardChrome,
      onSubmit: (content, parentCommentId) => ref
          .read(mushukistanApiProvider)
          .createComment(widget.postId, content,
              parentCommentId: parentCommentId),
      onRefresh: () => ref.invalidate(commentsProvider(widget.postId)),
      onMutation: () => ref.read(postMutationRevisionProvider.notifier).state++,
      currentUserId: currentUser?.id,
      isModerator: currentUser?.isModerator == true,
      isAuthenticated: isAuthenticated,
      onAuthenticationRequired: () => requestAuthentication(context),
      onEdit: api.updateComment,
      onDelete: api.deleteComment,
      now: widget.now,
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
    final currentUser = ref.watch(currentUserProvider);
    final isAuthenticated = ref.watch(
      authControllerProvider.select((state) => state.isAuthenticated),
    );
    final api = ref.read(mushukistanApiProvider);
    return _CommentsContent(
      commentsAsync: commentsAsync,
      strings: strings,
      padding: widget.padding,
      showCardChrome: widget.showCardChrome,
      onSubmit: (content, parentCommentId) =>
          ref.read(mushukistanApiProvider).createLostPetComment(
                widget.lostPetId,
                content,
                parentCommentId: parentCommentId,
              ),
      onRefresh: () =>
          ref.invalidate(lostPetCommentsProvider(widget.lostPetId)),
      onMutation: () => ref.read(postMutationRevisionProvider.notifier).state++,
      currentUserId: currentUser?.id,
      isModerator: currentUser?.isModerator == true,
      isAuthenticated: isAuthenticated,
      onAuthenticationRequired: () => requestAuthentication(context),
      onEdit: api.updateComment,
      onDelete: api.deleteComment,
      now: null,
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
    final currentUser = ref.watch(currentUserProvider);
    final isAuthenticated = ref.watch(
      authControllerProvider.select((state) => state.isAuthenticated),
    );
    final api = ref.read(mushukistanApiProvider);
    return _CommentsContent(
      commentsAsync: commentsAsync,
      strings: strings,
      padding: widget.padding,
      showCardChrome: widget.showCardChrome,
      onSubmit: (content, parentCommentId) =>
          ref.read(mushukistanApiProvider).createAdoptionPostComment(
                widget.adoptionPostId,
                content,
                parentCommentId: parentCommentId,
              ),
      onRefresh: () =>
          ref.invalidate(adoptionPostCommentsProvider(widget.adoptionPostId)),
      onMutation: () => ref.read(postMutationRevisionProvider.notifier).state++,
      currentUserId: currentUser?.id,
      isModerator: currentUser?.isModerator == true,
      isAuthenticated: isAuthenticated,
      onAuthenticationRequired: () => requestAuthentication(context),
      onEdit: api.updateComment,
      onDelete: api.deleteComment,
      now: null,
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
    required this.onMutation,
    required this.currentUserId,
    required this.isModerator,
    required this.isAuthenticated,
    required this.onAuthenticationRequired,
    required this.onEdit,
    required this.onDelete,
    required this.now,
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
  final VoidCallback onMutation;
  final String? currentUserId;
  final bool isModerator;
  final bool isAuthenticated;
  final VoidCallback onAuthenticationRequired;
  final Future<CommentData> Function(String commentId, String content) onEdit;
  final Future<void> Function(String commentId) onDelete;
  final DateTime? now;
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
  final Map<String, CommentData> _updatedComments = <String, CommentData>{};
  final Set<String> _removedCommentIds = <String>{};
  final Set<String> _expiredEditCommentIds = <String>{};
  String? _busyCommentId;

  bool _canEdit(CommentData comment) {
    if (widget.currentUserId == null ||
        comment.user?.id != widget.currentUserId ||
        _expiredEditCommentIds.contains(comment.id)) {
      return false;
    }
    return isCommentEditable(comment, now: widget.now);
  }

  bool _canDelete(CommentData comment) {
    return widget.currentUserId != null &&
        (comment.user?.id == widget.currentUserId || widget.isModerator);
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _editComment(CommentData comment) async {
    final editedContent = await showDialog<String>(
      context: context,
      builder: (_) => _CommentEditDialog(
        initialContent: comment.content,
        strings: widget.strings,
      ),
    );
    if (!mounted || editedContent == null || editedContent == comment.content) {
      return;
    }

    setState(() => _busyCommentId = comment.id);
    widget.setError(null);
    try {
      final updated = await widget.onEdit(comment.id, editedContent);
      if (!mounted) return;
      setState(() => _updatedComments[comment.id] = updated);
      widget.onRefresh();
      widget.onMutation();
      _showSuccess(widget.strings.commentUpdated);
    } catch (error) {
      if (error is MushukistanApiException &&
          error.code == 'COMMENT_EDIT_WINDOW_EXPIRED' &&
          mounted) {
        setState(() => _expiredEditCommentIds.add(comment.id));
      }
      widget.setError(
        error is MushukistanApiException
            ? error.userMessage
            : widget.strings.couldNotSaveChanges,
      );
    } finally {
      if (mounted) setState(() => _busyCommentId = null);
    }
  }

  Future<void> _deleteComment(CommentData comment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(widget.strings.deleteCommentTitle),
        content: Text(widget.strings.deleteCommentMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(widget.strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(widget.strings.delete),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;

    setState(() => _busyCommentId = comment.id);
    widget.setError(null);
    try {
      await widget.onDelete(comment.id);
      if (!mounted) return;
      setState(() {
        _removedCommentIds.add(comment.id);
        if (_replyingTo?.id == comment.id) _replyingTo = null;
      });
      widget.onRefresh();
      widget.onMutation();
      _showSuccess(widget.strings.commentDeleted);
    } catch (error) {
      widget.setError(
        error is MushukistanApiException
            ? error.userMessage
            : widget.strings.couldNotSaveChanges,
      );
    } finally {
      if (mounted) setState(() => _busyCommentId = null);
    }
  }

  Future<void> _submit() async {
    if (!widget.isAuthenticated) {
      widget.onAuthenticationRequired();
      return;
    }
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
      widget.onMutation();
      _showSuccess(widget.strings.commentPosted);
      if (mounted) {
        setState(() {
          _replyingTo = null;
        });
      }
    } catch (error) {
      widget.setError(
        error is MushukistanApiException
            ? error.userMessage
            : widget.strings.couldNotSaveChanges,
      );
    } finally {
      widget.setSubmitting(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.commentsAsync.when(
      data: (page) {
        final visibleComments = page.items
            .where((comment) => !_removedCommentIds.contains(comment.id))
            .map((comment) => _updatedComments[comment.id] ?? comment)
            .toList(growable: false);
        final roots = _buildCommentTree(visibleComments);
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
                  '${visibleComments.length}',
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
                      readOnly: !widget.isAuthenticated,
                      onTap: widget.isAuthenticated
                          ? null
                          : widget.onAuthenticationRequired,
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
            if (visibleComments.isEmpty)
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
                  currentUserId: widget.currentUserId,
                  isModerator: widget.isModerator,
                  canEdit: _canEdit,
                  canDelete: _canDelete,
                  isBusy: (comment) => _busyCommentId == comment.id,
                  onEdit: _editComment,
                  onDelete: _deleteComment,
                  onReply: (comment) {
                    if (!widget.isAuthenticated) {
                      widget.onAuthenticationRequired();
                      return;
                    }
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
      error: (error, stackTrace) => AppStatePanel(
        icon: Icons.error_outline,
        title: widget.strings.comments,
        message: widget.strings.couldNotLoadSection,
        action: FilledButton(
          onPressed: widget.onRefresh,
          child: Text(widget.strings.retry),
        ),
      ),
    );
  }
}

class _CommentEditDialog extends StatefulWidget {
  const _CommentEditDialog({
    required this.initialContent,
    required this.strings,
  });

  final String initialContent;
  final AppStrings strings;

  @override
  State<_CommentEditDialog> createState() => _CommentEditDialogState();
}

class _CommentEditDialogState extends State<_CommentEditDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialContent);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.strings.editComment),
      content: TextField(
        controller: _controller,
        autofocus: true,
        minLines: 1,
        maxLines: 6,
        maxLength: 1000,
        decoration: const InputDecoration(border: OutlineInputBorder()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.strings.cancel),
        ),
        FilledButton(
          onPressed: () {
            final value = _controller.text.trim();
            if (value.isNotEmpty) {
              Navigator.of(context).pop(value);
            }
          },
          child: Text(widget.strings.saveChanges),
        ),
      ],
    );
  }
}

class _CommentThread extends StatelessWidget {
  const _CommentThread({
    required this.node,
    required this.depth,
    required this.strings,
    required this.currentUserId,
    required this.isModerator,
    required this.canEdit,
    required this.canDelete,
    required this.isBusy,
    required this.onEdit,
    required this.onDelete,
    required this.onReply,
  });

  final _CommentTreeNode node;
  final int depth;
  final AppStrings strings;
  final String? currentUserId;
  final bool isModerator;
  final bool Function(CommentData comment) canEdit;
  final bool Function(CommentData comment) canDelete;
  final bool Function(CommentData comment) isBusy;
  final Future<void> Function(CommentData comment) onEdit;
  final Future<void> Function(CommentData comment) onDelete;
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
            currentUserId: currentUserId,
            isModerator: isModerator,
            canEdit: canEdit(node.comment),
            canDelete: canDelete(node.comment),
            busy: isBusy(node.comment),
            onEdit: () => onEdit(node.comment),
            onDelete: () => onDelete(node.comment),
            onReply: () => onReply(node.comment),
          ),
          ...node.children.map(
            (child) => _CommentThread(
              node: child,
              depth: depth + 1,
              strings: strings,
              currentUserId: currentUserId,
              isModerator: isModerator,
              canEdit: canEdit,
              canDelete: canDelete,
              isBusy: isBusy,
              onEdit: onEdit,
              onDelete: onDelete,
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
    required this.currentUserId,
    required this.isModerator,
    required this.canEdit,
    required this.canDelete,
    required this.busy,
    required this.onEdit,
    required this.onDelete,
    required this.onReply,
  });

  final CommentData comment;
  final AppStrings strings;
  final String? currentUserId;
  final bool isModerator;
  final bool canEdit;
  final bool canDelete;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
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
        borderRadius: BorderRadius.circular(8),
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
                child:
                    avatarUrl == null ? Text(_avatarInitial(userName)) : null,
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
                          '${_formatDate(comment.createdAt)}${comment.editedAt == null ? '' : ' · ${strings.edited}'}',
                          softWrap: true,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: colors.onSurfaceVariant,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (canEdit || canDelete)
                PopupMenuButton<String>(
                  enabled: !busy,
                  tooltip: strings.editComment,
                  onSelected: (value) {
                    if (value == 'edit') onEdit();
                    if (value == 'delete') onDelete();
                  },
                  itemBuilder: (context) => [
                    if (canEdit)
                      PopupMenuItem<String>(
                        value: 'edit',
                        child: Text(strings.editComment),
                      ),
                    if (canDelete)
                      PopupMenuItem<String>(
                        value: 'delete',
                        child: Text(
                          isModerator && comment.user?.id != currentUserId
                              ? strings.deleteCommentAsModerator
                              : strings.deleteComment,
                        ),
                      ),
                  ],
                  icon: busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.more_vert, size: 20),
                )
              else
                const SizedBox(width: 48),
              IconButton(
                tooltip: strings.report,
                onPressed: () => context.push(
                  Uri(
                    path: '/report',
                    queryParameters: {
                      'type': 'comment',
                      'id': comment.id,
                      'label': comment.content,
                    },
                  ).toString(),
                ),
                icon: const Icon(Icons.flag_outlined, size: 20),
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
                  minimumSize: const Size(48, 48),
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

bool isCommentEditable(CommentData comment, {DateTime? now}) {
  final editUntil =
      comment.editUntil ?? comment.createdAt.add(const Duration(minutes: 30));
  return (now ?? DateTime.now()).toUtc().isBefore(editUntil.toUtc());
}

String _formatDate(DateTime dateTime) {
  final local = dateTime.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
}
