import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/mushukistan_api.dart';

final moderationReportsProvider =
    FutureProvider.autoDispose<ApiPage<ReportData>>((ref) async {
  return ref.watch(mushukistanApiProvider).listReports();
});

class ModerationReportsScreen extends ConsumerWidget {
  const ModerationReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportsAsync = ref.watch(moderationReportsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Moderation reports'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(moderationReportsProvider),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: reportsAsync.when(
        data: (page) {
          if (page.items.isEmpty) {
            return const Center(child: Text('No open reports.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(24),
            itemCount: page.items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final report = page.items[index];
              return Card(
                child: ListTile(
                  title: Text('${report.targetType} · ${report.status}'),
                  subtitle: Text(report.reason ?? 'No reason provided'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/moderation/reports/${report.id}'),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(child: Text(error.toString())),
      ),
    );
  }
}
