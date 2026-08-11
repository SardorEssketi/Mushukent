import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/network/mushukistan_api.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/widgets/app_surface.dart';

final leaderboardTypeProvider = StateProvider<String>((ref) => 'most_active');
final leaderboardPeriodProvider = StateProvider<String>((ref) => 'week');

final leaderboardProvider =
    FutureProvider.autoDispose<List<LeaderboardEntryData>>((ref) async {
  final api = ref.watch(mushukistanApiProvider);
  final type = ref.watch(leaderboardTypeProvider);
  final period = ref.watch(leaderboardPeriodProvider);
  return api.listLeaderboard(type, period: period, limit: 20);
});

class LeaderboardScreen extends ConsumerWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final type = ref.watch(leaderboardTypeProvider);
    final period = ref.watch(leaderboardPeriodProvider);
    final leaderboardAsync = ref.watch(leaderboardProvider);
    final strings = ref.watch(appStringsProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppContentWidth(
              maxWidth: AppWidths.readable,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Community',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Recognition for people helping cats through observations, comments, and support.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ),
            _LeaderboardControls(
              type: type,
              period: period,
              strings: strings,
              onTypeChanged: (value) {
                ref.read(leaderboardTypeProvider.notifier).state = value;
                ref.invalidate(leaderboardProvider);
              },
              onPeriodChanged: (value) {
                ref.read(leaderboardPeriodProvider.notifier).state = value;
                ref.invalidate(leaderboardProvider);
              },
            ),
            Expanded(
              child: leaderboardAsync.when(
                data: (entries) {
                  if (entries.isEmpty) {
                    return _EmptyLeaderboard(
                        message: strings.noLeaderboardData);
                  }
                  return AppContentWidth(
                    maxWidth: AppWidths.readable,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      itemCount: entries.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        return _LeaderboardTile(
                          entry: entry,
                          strings: strings,
                        );
                      },
                    ),
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stackTrace) => _ErrorPanel(
                  message: error.toString(),
                  retryLabel: strings.retry,
                  onRetry: () => ref.invalidate(leaderboardProvider),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LeaderboardControls extends StatelessWidget {
  const _LeaderboardControls({
    required this.type,
    required this.period,
    required this.strings,
    required this.onTypeChanged,
    required this.onPeriodChanged,
  });

  final String type;
  final String period;
  final AppStrings strings;
  final ValueChanged<String> onTypeChanged;
  final ValueChanged<String> onPeriodChanged;

  @override
  Widget build(BuildContext context) {
    return AppContentWidth(
      maxWidth: AppWidths.readable,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                selected: {type},
                onSelectionChanged: (values) => onTypeChanged(values.first),
                segments: [
                  ButtonSegment(
                    value: 'most_active',
                    icon: const Icon(Icons.directions_walk),
                    label: Text(strings.mostActive),
                  ),
                  ButtonSegment(
                    value: 'most_popular',
                    icon: const Icon(Icons.favorite_border),
                    label: Text(strings.mostPopular),
                  ),
                  ButtonSegment(
                    value: 'top_helpers',
                    icon: const Icon(Icons.volunteer_activism_outlined),
                    label: Text(strings.topHelpers),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                selected: {period},
                onSelectionChanged: (values) => onPeriodChanged(values.first),
                segments: [
                  ButtonSegment(value: 'day', label: Text(strings.day)),
                  ButtonSegment(value: 'week', label: Text(strings.week)),
                  ButtonSegment(value: 'month', label: Text(strings.month)),
                  ButtonSegment(value: 'all', label: Text(strings.allTime)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LeaderboardTile extends StatelessWidget {
  const _LeaderboardTile({required this.entry, required this.strings});

  final LeaderboardEntryData entry;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final userName = entry.user.name ?? strings.unnamedUser;
    return AppCard(
      onTap: () => context.push('/users/${entry.user.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          _RankBadge(rank: entry.rank),
          const SizedBox(width: 12),
          CircleAvatar(
            radius: 22,
            backgroundImage: entry.user.avatarUrl == null
                ? null
                : NetworkImage(entry.user.avatarUrl!),
            backgroundColor: colors.secondaryContainer,
            foregroundColor: colors.onSecondaryContainer,
            child:
                entry.user.avatarUrl == null ? Text(_initials(userName)) : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  userName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      Icons.photo_camera_outlined,
                      size: 16,
                      color: colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        '${entry.user.observationCount} ${strings.observations}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
              child: Column(
                children: [
                  Text(
                    '${entry.score}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: colors.onPrimaryContainer,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    strings.score,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank});

  final int rank;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final background = switch (rank) {
      1 => const Color(0xFFFFD54F),
      2 => const Color(0xFFCFD8DC),
      3 => const Color(0xFFD7A86E),
      _ => colors.surfaceContainerHighest,
    };
    final foreground = rank <= 3 ? Colors.black87 : colors.onSurfaceVariant;
    return Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Text(
        '#$rank',
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

class _EmptyLeaderboard extends StatelessWidget {
  const _EmptyLeaderboard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.leaderboard_outlined,
                  size: 36,
                  color: colors.primary,
                ),
                const SizedBox(height: 12),
                Text(message, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _initials(String name) {
  final parts = name.split(RegExp(r'\s+')).where((part) => part.isNotEmpty);
  final initials = parts.take(2).map((part) => part[0]).join();
  return initials.isEmpty ? 'MU' : initials.toUpperCase();
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({
    required this.message,
    required this.retryLabel,
    required this.onRetry,
  });

  final String message;
  final String retryLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: Text(retryLabel)),
          ],
        ),
      ),
    );
  }
}
