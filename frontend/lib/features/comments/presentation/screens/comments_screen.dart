import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/network/mushukistan_api.dart';

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
      onSubmit: (content) => ref
          .read(mushukistanApiProvider)
          .createComment(widget.postId, content),
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
      onSubmit: (content) => ref
          .read(mushukistanApiProvider)
          .createLostPetComment(widget.lostPetId, content),
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
      onSubmit: (content) => ref
          .read(mushukistanApiProvider)
          .createAdoptionPostComment(widget.adoptionPostId, content),
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

class _CommentsContent extends StatelessWidget {
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
  final Future<void> Function(String content) onSubmit;
  final VoidCallback onRefresh;
  final TextEditingController controller;
  final bool submitting;
  final String? error;
  final ValueChanged<bool> setSubmitting;
  final ValueChanged<String?> setError;

  @override
  Widget build(BuildContext context) {
    return commentsAsync.when(
      data: (page) {
        final content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Comments',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Add a comment',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: submitting
                  ? null
                  : () async {
                      final content = controller.text.trim();
                      if (content.isEmpty) {
                        return;
                      }
                      setSubmitting(true);
                      setError(null);
                      try {
                        await onSubmit(content);
                        controller.clear();
                        onRefresh();
                      } catch (error) {
                        setError(error.toString());
                      } finally {
                        setSubmitting(false);
                      }
                    },
              child: submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Post comment'),
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 24),
            if (page.items.isEmpty)
              const Text('No comments yet.')
            else
              ...page.items.map(
                (comment) {
                  final userId = comment.user?.id;
                  final userName = comment.user?.name ?? strings.anonymous;
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Text(_avatarInitial(userName)),
                      ),
                      title: Text(userName),
                      subtitle: Text(comment.content),
                      trailing: Text(_formatDate(comment.createdAt)),
                      onTap: userId == null
                          ? null
                          : () => context.push('/users/$userId'),
                    ),
                  );
                },
              ),
          ],
        );

        if (!showCardChrome) {
          return Padding(
            padding: padding,
            child: content,
          );
        }

        return Padding(
          padding: padding,
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
