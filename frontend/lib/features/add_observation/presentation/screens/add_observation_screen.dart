import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/add_observation_controller.dart';

class AddObservationScreen extends ConsumerWidget {
  const AddObservationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(addObservationControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Add')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Choose what you want to add.',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          const Text(
            'Each category has its own form and fields.',
          ),
          const SizedBox(height: 24),
          _AddCategoryCard(
            icon: Icons.add_a_photo_outlined,
            title: 'Street cat observation',
            subtitle: 'Photo, location, cat profile, and public feed details.',
            onTap: () => context.go('/add/entry'),
          ),
          const SizedBox(height: 12),
          _AddCategoryCard(
            icon: Icons.search_outlined,
            title: 'Lost pet',
            subtitle: 'Pet photo, last seen location, map, and owner contacts.',
            onTap: () => context.go('/add/lost-pet'),
          ),
          const SizedBox(height: 12),
          _AddCategoryCard(
            icon: Icons.home_outlined,
            title: 'Give pet for adoption',
            subtitle: 'Pet photo, description, and owner contacts. No map.',
            onTap: () => context.go('/add/adoption'),
          ),
          const SizedBox(height: 24),
          _SummaryCard(state: state),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: state.hasPhoto ? () => context.go('/add/details') : null,
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Continue draft'),
          ),
        ],
      ),
    );
  }
}

class _AddCategoryCard extends StatelessWidget {
  const _AddCategoryCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: colorScheme.primary),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.state});

  final AddObservationState state;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Draft status',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
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
