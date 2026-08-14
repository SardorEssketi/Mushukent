import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/widgets/app_surface.dart';
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
      appBar: AppBar(title: const Text('Cat observation')),
      body: AppContentWidth(
        maxWidth: AppWidths.readable,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            AppBadge(
              label:
                  state.hasLocation ? 'Located observation' : 'Feed-only post',
              icon: state.hasLocation
                  ? Icons.location_on_outlined
                  : Icons.dynamic_feed_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => context.go('/add/location'),
                icon: Icon(
                  state.hasLocation
                      ? Icons.edit_location_alt_outlined
                      : Icons.add_location_alt_outlined,
                ),
                label: Text(
                  state.hasLocation ? 'Change location' : 'Add location',
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Match the cat and add details',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.xl),
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
              const AppCard(
                child: Text(
                  'This gallery observation will appear in the feed only and will not create a map marker.',
                ),
              ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Description',
                hintText: 'Add a short note about the cat or location',
              ),
              maxLines: 4,
              onChanged: controller.setDescription,
            ),
            if (state.useNewCat) ...[
              const SizedBox(height: AppSpacing.lg),
              TextField(
                decoration: const InputDecoration(
                  labelText: 'New cat name (optional)',
                ),
                onChanged: controller.setNewCatName,
              ),
              if (state.hasLocation) ...[
                const SizedBox(height: AppSpacing.lg),
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
              const SizedBox(height: AppSpacing.lg),
              Text(
                state.errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
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
      ),
    );
  }
}
