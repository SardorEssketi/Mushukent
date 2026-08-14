import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/mushukistan_api.dart';
import '../../application/add_observation_controller.dart';

class PublishSuccessScreen extends ConsumerWidget {
  const PublishSuccessScreen({super.key, this.post});

  final PostDetail? post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final createdPost = post;
    final state = ref.watch(addObservationControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Published')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 72,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Observation published.',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    createdPost != null
                        ? 'Post ${createdPost.id} is now available in the feed.'
                        : 'Your observation has been sent to the backend.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  if (createdPost != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 240),
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: Image.network(
                            createdPost.thumbUrl ?? createdPost.photoUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return ColoredBox(
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                                child: Icon(
                                  Icons.image_not_supported_outlined,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                  size: 48,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    _SummaryRow(
                        label: 'Cat',
                        value: createdPost.cat.name ?? 'Unnamed cat'),
                    const SizedBox(height: 24),
                  ],
                  FilledButton(
                    onPressed: () {
                      ref
                          .read(addObservationControllerProvider.notifier)
                          .reset();
                      context.go('/feed');
                    },
                    child: const Text('View feed'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () {
                      ref
                          .read(addObservationControllerProvider.notifier)
                          .reset();
                      context.go('/add/entry');
                    },
                    child: const Text('Add another'),
                  ),
                  if (state.errorMessage != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      state.errorMessage!,
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
