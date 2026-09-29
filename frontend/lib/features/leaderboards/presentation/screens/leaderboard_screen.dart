import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/network/mushukistan_api.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/widgets/app_surface.dart';

final leaderboardTypeProvider = StateProvider<String>((ref) => 'most_active');
final leaderboardPeriodProvider = StateProvider<String>((ref) => 'month');

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
                child: Text(
                  strings.leaderboard,
                  style: Theme.of(context).textTheme.headlineSmall,
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
                      message: strings.noLeaderboardData,
                    );
                  }
                  return _LeaderboardResults(
                    entries: entries,
                    type: type,
                    strings: strings,
                  );
                },
                loading: () => const Center(
                  child: CircularProgressIndicator(),
                ),
                error: (error, stackTrace) => AppStatePanel(
                  icon: Icons.error_outline,
                  title: strings.leaderboard,
                  message: strings.couldNotLoadSection,
                  action: FilledButton(
                    onPressed: () => ref.invalidate(leaderboardProvider),
                    child: Text(strings.retry),
                  ),
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
    final typeSelector = SegmentedButton<String>(
      showSelectedIcon: false,
      segments: [
        ButtonSegment<String>(
          value: 'most_active',
          label: Text(strings.mostActive),
        ),
        ButtonSegment<String>(
          value: 'most_popular',
          label: Text(strings.mostPopular),
        ),
      ],
      selected: {type},
      onSelectionChanged: (selection) {
        if (selection.isNotEmpty) onTypeChanged(selection.first);
      },
    );

    final periodSelector = PopupMenuButton<String>(
      initialValue: period,
      onSelected: onPeriodChanged,
      itemBuilder: (context) => [
        PopupMenuItem(value: 'day', child: Text(strings.day)),
        PopupMenuItem(value: 'week', child: Text(strings.week)),
        PopupMenuItem(value: 'month', child: Text(strings.month)),
        PopupMenuItem(value: 'all', child: Text(strings.allTime)),
      ],
      child: DecoratedBox(
        decoration: BoxDecoration(
          border:
              Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_periodLabel(period, strings)),
              const SizedBox(width: 4),
              const Icon(Icons.expand_more, size: 20),
            ],
          ),
        ),
      ),
    );

    return AppContentWidth(
      maxWidth: AppWidths.readable,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 460) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  typeSelector,
                  Align(
                    alignment: Alignment.centerRight,
                    child: periodSelector,
                  ),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: typeSelector),
                const SizedBox(width: 12),
                periodSelector,
              ],
            );
          },
        ),
      ),
    );
  }
}

String _periodLabel(String period, AppStrings strings) => switch (period) {
      'day' => strings.day,
      'week' => strings.week,
      'month' => strings.thisMonth,
      _ => strings.allTime,
    };

class _LeaderboardResults extends StatelessWidget {
  const _LeaderboardResults({
    required this.entries,
    required this.type,
    required this.strings,
  });

  final List<LeaderboardEntryData> entries;
  final String type;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return AppContentWidth(
      maxWidth: AppWidths.readable,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final topThree = entries.take(3).toList(growable: false);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            children: [
              _TopThree(
                entries: topThree,
                type: type,
                strings: strings,
                compact: constraints.maxWidth < 560,
              ),
              if (entries.length > 3) ...[
                const SizedBox(height: 12),
                Column(
                  children: [
                    for (var index = 3; index < entries.length; index++) ...[
                      _LeaderboardListTile(
                        entry: entries[index],
                        type: type,
                        strings: strings,
                      ),
                      if (index < entries.length - 1)
                        const Divider(height: 1, indent: 48),
                    ],
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _TopThree extends StatelessWidget {
  const _TopThree({
    required this.entries,
    required this.type,
    required this.strings,
    required this.compact,
  });

  final List<LeaderboardEntryData> entries;
  final String type;
  final AppStrings strings;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Column(
        children: [
          for (final entry in entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _TopLeaderboardCard(
                entry: entry,
                type: type,
                strings: strings,
                compact: true,
              ),
            ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in entries)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: _TopLeaderboardCard(
                entry: entry,
                type: type,
                strings: strings,
                compact: false,
              ),
            ),
          ),
      ],
    );
  }
}

class _TopLeaderboardCard extends StatelessWidget {
  const _TopLeaderboardCard({
    required this.entry,
    required this.type,
    required this.strings,
    required this.compact,
  });

  final LeaderboardEntryData entry;
  final String type;
  final AppStrings strings;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final name = entry.user.name ?? strings.unnamedUser;
    final borderColor =
        entry.rank == 1 ? colors.primary : colors.outlineVariant;
    final metric = _metricText(entry, type, strings);

    return Card(
      margin: EdgeInsets.zero,
      color: entry.rank == 1
          ? colors.primaryContainer
          : colors.surfaceContainerLow,
      elevation: entry.rank == 1 ? 1 : 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        side: BorderSide(
          color: borderColor,
          width: entry.rank == 1 ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/users/${entry.user.id}'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: compact
              ? Row(
                  children: [
                    _RankBadge(rank: entry.rank),
                    const SizedBox(width: 10),
                    _UserAvatar(user: entry.user, name: name, radius: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _UserName(name: name, textAlign: TextAlign.start),
                          const SizedBox(height: 4),
                          _MetricLabel(text: metric, align: TextAlign.start),
                        ],
                      ),
                    ),
                  ],
                )
              : Column(
                  children: [
                    _RankBadge(rank: entry.rank),
                    const SizedBox(height: 10),
                    _UserAvatar(user: entry.user, name: name, radius: 25),
                    const SizedBox(height: 10),
                    _UserName(name: name, textAlign: TextAlign.center),
                    const SizedBox(height: 6),
                    _MetricLabel(text: metric, align: TextAlign.center),
                  ],
                ),
        ),
      ),
    );
  }
}

class _LeaderboardListTile extends StatelessWidget {
  const _LeaderboardListTile({
    required this.entry,
    required this.type,
    required this.strings,
  });

  final LeaderboardEntryData entry;
  final String type;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final name = entry.user.name ?? strings.unnamedUser;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.md),
      onTap: () => context.push('/users/${entry.user.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          children: [
            _RankBadge(rank: entry.rank),
            const SizedBox(width: 8),
            _UserAvatar(user: entry.user, name: name, radius: 18),
            const SizedBox(width: 10),
            Expanded(child: _UserName(name: name, textAlign: TextAlign.start)),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 112),
              child: _MetricLabel(
                text: _metricText(entry, type, strings),
                align: TextAlign.end,
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UserAvatar extends StatelessWidget {
  const _UserAvatar({
    required this.user,
    required this.name,
    required this.radius,
  });

  final LeaderboardUserData user;
  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: radius,
      backgroundImage:
          user.avatarUrl == null ? null : NetworkImage(user.avatarUrl!),
      backgroundColor: colors.secondaryContainer,
      foregroundColor: colors.onSecondaryContainer,
      child: user.avatarUrl == null ? Text(_initials(name)) : null,
    );
  }
}

class _UserName extends StatelessWidget {
  const _UserName({required this.name, required this.textAlign});

  final String name;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    return Text(
      name,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: textAlign,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
    );
  }
}

class _MetricLabel extends StatelessWidget {
  const _MetricLabel({
    required this.text,
    required this.align,
    this.color,
  });

  final String text;
  final TextAlign align;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: align,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
    );
  }
}

String _metricText(
  LeaderboardEntryData entry,
  String type,
  AppStrings strings,
) {
  if (type == 'most_popular') {
    return '${entry.likeCount} ${strings.likes}';
  }
  return '${entry.observationCount} ${strings.observations}';
}

class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank});

  final int rank;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final background = switch (rank) {
      1 => colors.primary,
      2 => colors.secondaryContainer,
      3 => colors.tertiaryContainer,
      _ => colors.surfaceContainerHighest,
    };
    final foreground = switch (rank) {
      1 => colors.onPrimary,
      2 => colors.onSecondaryContainer,
      3 => colors.onTertiaryContainer,
      _ => colors.onSurfaceVariant,
    };
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Text(
        '#$rank',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
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
    return AppStatePanel(
      icon: Icons.leaderboard_outlined,
      title: message,
    );
  }
}

String _initials(String name) {
  final parts = name.split(RegExp(r'\s+')).where((part) => part.isNotEmpty);
  final initials = parts.take(2).map((part) => part[0]).join();
  return initials.isEmpty ? 'MU' : initials.toUpperCase();
}
