import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/network/mushukistan_api.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../../auth/application/auth_controller.dart';

final postHistoryProvider = FutureProvider.autoDispose
    .family<List<PostHistoryEntry>, String>((ref, postId) {
  return ref.watch(mushukistanApiProvider).getPostHistory(postId);
});

class PostHistoryScreen extends ConsumerWidget {
  const PostHistoryScreen({super.key, required this.postId});

  final String postId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final isModerator = ref.watch(currentUserProvider)?.isModerator == true;
    if (!isModerator) {
      return Scaffold(
        appBar: AppBar(title: Text(strings.postHistory)),
        body: AppStatePanel(
          icon: Icons.lock_outline,
          title: strings.postHistory,
          message: strings.moderatorOnlyHistory,
        ),
      );
    }
    final historyAsync = ref.watch(postHistoryProvider(postId));
    return Scaffold(
      appBar: AppBar(title: Text(strings.postHistory)),
      body: historyAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => AppStatePanel(
          icon: Icons.error_outline,
          title: strings.postHistory,
          message: strings.couldNotLoadSection,
          action: FilledButton(
            onPressed: () => ref.invalidate(postHistoryProvider(postId)),
            child: Text(strings.retry),
          ),
        ),
        data: (entries) {
          if (entries.isEmpty) {
            return Center(child: Text(strings.noObservationsYet));
          }
          return AppContentWidth(
            maxWidth: AppWidths.readable,
            child: ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.lg),
              itemCount: entries.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppSpacing.md),
              itemBuilder: (context, index) => _HistoryCard(
                entry: entries[index],
                strings: strings,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.entry, required this.strings});

  final PostHistoryEntry entry;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final changedEntries = entry.before.entries.where(
      (item) => !historyValuesEqual(item.value, entry.after[item.key]),
    );
    final deleted = entry.action == 'deleted';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              deleted ? strings.historyRemoved : strings.edited,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(_formatTimestamp(entry.createdAt)),
            if (entry.actorName?.trim().isNotEmpty == true) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(entry.actorName!),
            ],
            if (deleted) ...[
              const SizedBox(height: AppSpacing.md),
              Text(strings.historyDeletedMessage),
              const SizedBox(height: AppSpacing.sm),
              _SnapshotValue(
                label: strings.previousVersion,
                value: entry.before,
                strings: strings,
              ),
            ] else if (changedEntries.isEmpty)
              const SizedBox.shrink()
            else ...[
              const SizedBox(height: AppSpacing.md),
              ...changedEntries.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: _ChangedValue(
                    label: _labelFor(item.key, strings),
                    before: item.value,
                    after: entry.after[item.key],
                    strings: strings,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ChangedValue extends StatelessWidget {
  const _ChangedValue({
    required this.label,
    required this.before,
    required this.after,
    required this.strings,
  });

  final String label;
  final Object? before;
  final Object? after;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        Text('${strings.before}: ${_displayValue(before, strings)}'),
        Text('${strings.after}: ${_displayValue(after, strings)}'),
      ],
    );
  }
}

class _SnapshotValue extends StatelessWidget {
  const _SnapshotValue({
    required this.label,
    required this.value,
    required this.strings,
  });

  final String label;
  final Map<String, Object?> value;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        ...value.entries.map(
          (item) => Text(
            '${_labelFor(item.key, strings)}: ${_displayValue(item.value, strings)}',
          ),
        ),
      ],
    );
  }
}

String _labelFor(String key, AppStrings strings) {
  return switch (key) {
    'description' => strings.descriptionLabel,
    'kind' => strings.addObservation,
    'status' => strings.catStatus,
    'location' => strings.location,
    'is_public' => strings.visibility,
    'photo_urls' => strings.photos,
    _ => key,
  };
}

String _displayValue(Object? value, AppStrings strings) {
  if (value == null) {
    return strings.noValue;
  }
  if (value is List) {
    return value.isEmpty
        ? strings.noPhotos
        : value.map((item) => item.toString()).join('\n');
  }
  if (value is Map) {
    final latitude = value['latitude'];
    final longitude = value['longitude'];
    if (latitude != null && longitude != null) {
      return '$latitude, $longitude';
    }
  }
  return value.toString();
}

bool historyValuesEqual(Object? first, Object? second) {
  if (first is List && second is List) {
    if (first.length != second.length) {
      return false;
    }
    for (var index = 0; index < first.length; index++) {
      if (!historyValuesEqual(first[index], second[index])) {
        return false;
      }
    }
    return true;
  }
  if (first is Map && second is Map) {
    if (first.length != second.length) {
      return false;
    }
    for (final key in first.keys) {
      if (!second.containsKey(key) ||
          !historyValuesEqual(first[key], second[key])) {
        return false;
      }
    }
    return true;
  }
  return first == second;
}

String _formatTimestamp(DateTime value) {
  final local = value.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}
