import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/mushukistan_api.dart';
import '../../application/add_observation_controller.dart';
import '../../../feed/presentation/screens/feed_screen.dart';
import '../../../leaderboards/presentation/screens/leaderboard_screen.dart';
import '../../../map/presentation/screens/map_screen.dart';
import '../../../profile/presentation/screens/profile_screen.dart';
import '../widgets/cat_preview_sheet.dart';

class AddObservationDetailsScreen extends ConsumerWidget {
  const AddObservationDetailsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(addObservationControllerProvider);
    final controller = ref.read(addObservationControllerProvider.notifier);
    final cats = state.nearbyCats.asData?.value?.items ?? const <CatSummary>[];

    if (!state.hasPhoto) {
      return Scaffold(
        appBar: AppBar(title: const Text('Add Observation')),
        body: const Center(
          child: Text('Choose a photo first.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Add Observation')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            state.hasLocation ? 'Camera observation' : 'Feed-only observation',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Match the cat and add details.',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 24),
          if (state.hasLocation)
            CatPreviewSheet(
              cats: cats,
              selectedCatId: state.selectedCatId,
              useNewCat: state.useNewCat,
              onSelectCat: (value) {
                controller.setSelectedCat(value);
              },
              onUseNewCat: () => controller.setUseNewCat(true),
            )
          else
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'This gallery observation will appear in the feed only and will not create a map marker.',
                ),
              ),
            ),
          const SizedBox(height: 16),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Description',
              hintText: 'Add a short note about the cat or location',
            ),
            maxLines: 4,
            onChanged: controller.setDescription,
          ),
          if (state.useNewCat) ...[
            const SizedBox(height: 16),
            TextField(
              decoration: const InputDecoration(
                labelText: 'New cat name (optional)',
              ),
              onChanged: controller.setNewCatName,
            ),
            if (state.hasLocation) ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: state.newCatStatus,
                items: const [
                  DropdownMenuItem(value: 'unknown', child: Text('Unknown')),
                  DropdownMenuItem(value: 'healthy', child: Text('Healthy')),
                  DropdownMenuItem(
                    value: 'needs_help',
                    child: Text('Needs help'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    controller.setNewCatStatus(value);
                  }
                },
                decoration: const InputDecoration(labelText: 'Cat status'),
              ),
            ],
          ],
          if (state.errorMessage != null) ...[
            const SizedBox(height: 16),
            Text(
              state.errorMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: state.submitting
                ? null
                : () async {
                    try {
                      final post = await controller.submit();
                      ref.invalidate(feedPostsProvider);
                      ref.invalidate(mapCatsProvider);
                      ref.invalidate(profileMeProvider);
                      ref.invalidate(leaderboardProvider);
                      if (context.mounted) {
                        context.go('/add/success', extra: post);
                      }
                    } catch (_) {
                      // Error is surfaced by controller state.
                    }
                  },
            child: state.submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Publish observation'),
          ),
        ],
      ),
    );
  }
}
