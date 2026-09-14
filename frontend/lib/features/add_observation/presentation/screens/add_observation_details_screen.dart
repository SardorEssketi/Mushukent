import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../application/add_observation_controller.dart';
import '../../../feed/presentation/screens/feed_screen.dart';
import '../../../leaderboards/presentation/screens/leaderboard_screen.dart';
import '../../../map/presentation/screens/map_screen.dart';
import '../../../profile/presentation/screens/profile_screen.dart';

class AddObservationDetailsScreen extends ConsumerWidget {
  const AddObservationDetailsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(addObservationControllerProvider);
    final controller = ref.read(addObservationControllerProvider.notifier);
    final strings = ref.watch(appStringsProvider);

    if (!state.hasPhoto) {
      return Scaffold(
        appBar: AppBar(title: Text(strings.addObservation)),
        body: Center(
          child: Text(strings.choosePhotoFirst),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(strings.catObservation)),
      body: AppContentWidth(
        maxWidth: AppWidths.readable,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            AppBadge(
              label: state.hasLocation
                  ? strings.locatedObservation
                  : strings.feedOnlyPost,
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
                  state.hasLocation
                      ? strings.changeLocation
                      : strings.addLocation,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              strings.catObservation,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.xl),
            if (!state.hasLocation)
              AppCard(
                child: Text(
                  strings.feedOnlyObservationHelp,
                ),
              ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              decoration: InputDecoration(
                labelText: strings.descriptionLabel,
                hintText: strings.descriptionHint,
              ),
              maxLines: 4,
              onChanged: controller.setDescription,
            ),
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
                  : Text(strings.publishObservation),
            ),
          ],
        ),
      ),
    );
  }
}
