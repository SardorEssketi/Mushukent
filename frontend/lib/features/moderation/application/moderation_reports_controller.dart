import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/mushukistan_api.dart';

/// Report status filters of the moderation queue, in display order.
const moderationReportStatuses = <String>['open', 'resolved', 'dismissed'];

/// The queue filter currently selected; kept while the moderator opens and
/// leaves report details.
final moderationStatusFilterProvider = StateProvider<String>((ref) => 'open');

class ModerationReportList {
  const ModerationReportList({
    required this.items,
    required this.nextCursor,
    this.loadingMore = false,
    this.loadMoreError,
  });

  final List<ReportData> items;
  final String? nextCursor;
  final bool loadingMore;
  final Object? loadMoreError;

  bool get hasMore => nextCursor != null;
}

/// One status of the moderation queue, paginated with the API cursor.
class ModerationReportsController
    extends AutoDisposeFamilyAsyncNotifier<ModerationReportList, String> {
  int _generation = 0;

  @override
  Future<ModerationReportList> build(String status) async {
    _generation++;
    ref.onDispose(() => _generation++);
    final page =
        await ref.watch(mushukistanApiProvider).listReports(status: status);
    return ModerationReportList(
      items: _merge(const [], page.items),
      nextCursor: page.nextCursor,
    );
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || current.loadingMore || !current.hasMore) return;
    final generation = _generation;
    state = AsyncData(ModerationReportList(
      items: current.items,
      nextCursor: current.nextCursor,
      loadingMore: true,
    ));
    try {
      final page = await ref
          .read(mushukistanApiProvider)
          .listReports(status: arg, cursor: current.nextCursor);
      if (generation != _generation) return;
      state = AsyncData(ModerationReportList(
        items: _merge(current.items, page.items),
        nextCursor: page.nextCursor,
      ));
    } catch (error) {
      if (generation != _generation) return;
      state = AsyncData(ModerationReportList(
        items: current.items,
        nextCursor: current.nextCursor,
        loadMoreError: error,
      ));
    }
  }

  /// Keeps API order and drops reports already listed (a report handled or
  /// added between page loads must not appear twice).
  static List<ReportData> _merge(
    List<ReportData> existing,
    List<ReportData> incoming,
  ) {
    final seen = {for (final report in existing) report.id};
    return List<ReportData>.unmodifiable([
      ...existing,
      for (final report in incoming)
        if (seen.add(report.id)) report,
    ]);
  }
}

final moderationReportsProvider = AsyncNotifierProvider.autoDispose
    .family<ModerationReportsController, ModerationReportList, String>(
  ModerationReportsController.new,
);

/// Invalidate every queue status after a decision, so the report leaves Open
/// and appears under its new status.
void invalidateModerationQueues(WidgetRef ref) {
  ref.invalidate(moderationReportsProvider);
}
