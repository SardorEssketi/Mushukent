import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../application/add_observation_controller.dart';

class AddObservationScreen extends ConsumerWidget {
  const AddObservationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(addObservationControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Create')),
      body: AppContentWidth(
        maxWidth: AppWidths.readable,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            Text(
              'What are you creating?',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Choose the right type first so Mushukistan can ask only for the details that matter.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: AppSpacing.xl),
            _AddCategoryCard(
              icon: Icons.add_a_photo_outlined,
              title: 'Cat observation',
              subtitle:
                  'Photo, optional map location, cat profile, and feed details.',
              color: Theme.of(context).colorScheme.primary,
              onTap: () => context.go('/add/entry'),
            ),
            const SizedBox(height: AppSpacing.md),
            _AddCategoryCard(
              icon: Icons.search_outlined,
              title: 'Lost pet alert',
              subtitle:
                  'Pet photos, last-seen map point, status, and owner contact.',
              color: Theme.of(context).colorScheme.error,
              onTap: () => context.go('/add/lost-pet'),
            ),
            const SizedBox(height: AppSpacing.md),
            _AddCategoryCard(
              icon: Icons.home_outlined,
              title: 'Find a new home',
              subtitle:
                  'A separate rehoming post with photos, description, and owner contact. No map required.',
              color: AppPalette.adoption,
              onTap: () => context.go('/add/adoption'),
            ),
            const SizedBox(height: AppSpacing.xl),
            _SummaryCard(state: state),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed:
                  state.hasPhoto ? () => context.go('/add/details') : null,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Continue draft'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddCategoryCard extends StatelessWidget {
  const _AddCategoryCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.12),
            foregroundColor: color,
            child: Icon(icon),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.state});

  final AddObservationState state;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Draft status', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.md),
          _SummaryRow(
              label: 'Photo', value: state.hasPhoto ? 'Selected' : 'Missing'),
          _SummaryRow(
            label: 'Location',
            value: state.hasLocation ? 'Set' : 'Missing',
          ),
          _SummaryRow(
            label: 'Cat choice',
            value: state.useNewCat ? 'New cat' : 'Existing cat',
          ),
          _SummaryRow(
            label: 'Visibility',
            value: state.isPublic ? 'Public' : 'Private',
          ),
        ],
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
