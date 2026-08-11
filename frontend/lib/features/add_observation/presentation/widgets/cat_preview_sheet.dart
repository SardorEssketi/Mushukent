import 'package:flutter/material.dart';

import '../../../../core/network/mushukistan_api.dart';

class CatPreviewSheet extends StatelessWidget {
  const CatPreviewSheet({
    super.key,
    required this.cats,
    required this.selectedCatId,
    required this.useNewCat,
    required this.onSelectCat,
    required this.onUseNewCat,
  });

  final List<CatSummary> cats;
  final String? selectedCatId;
  final bool useNewCat;
  final ValueChanged<String?> onSelectCat;
  final VoidCallback onUseNewCat;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nearby cats', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            if (cats.isEmpty)
              const Text('No nearby cats found.')
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final cat in cats)
                    ChoiceChip(
                      label: Text(cat.name ?? 'Unnamed cat'),
                      selected: selectedCatId == cat.id,
                      onSelected: (selected) {
                        if (selected) {
                          onSelectCat(cat.id);
                        } else {
                          onSelectCat(null);
                        }
                      },
                    ),
                ],
              ),
            const Divider(height: 24),
            Align(
              alignment: Alignment.centerLeft,
              child: ChoiceChip(
                selected: useNewCat,
                onSelected: (_) => onUseNewCat(),
                avatar: const Icon(Icons.add_circle_outline, size: 18),
                label: const Text('This is a new cat'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
