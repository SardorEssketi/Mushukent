import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/network/mushukistan_api.dart';

/// User-facing labels for moderation API values. The API values themselves
/// (`post`, `resolved`, `soft_delete_post`, ...) are never shown: unknown or
/// future values get a neutral localized fallback instead of the raw code.

String reportStatusLabel(AppStrings strings, String status) => switch (status) {
      'open' => strings.reportStatusOpen,
      'resolved' => strings.reportStatusResolved,
      'dismissed' => strings.reportStatusDismissed,
      _ => strings.reportStatusUnknown,
    };

String reportTargetTypeLabel(AppStrings strings, String targetType) =>
    switch (targetType) {
      'post' => strings.reportTargetPost,
      'comment' => strings.reportTargetComment,
      'user' => strings.reportTargetUser,
      'cat' => strings.reportTargetCat,
      'lost_pet' => strings.reportTargetLostPet,
      'adoption_post' => strings.reportTargetAdoptionPost,
      _ => strings.reportTargetOther,
    };

/// What a moderator needs to know about the reported content right now.
enum ReportTargetState { visible, private, deleted, suspended, unavailable }

ReportTargetState reportTargetState(ReportData report) {
  final target = report.target;
  if (target == null) return ReportTargetState.unavailable;
  if (target.isActive == false || target.deletedAt != null) {
    return report.targetType == 'user'
        ? ReportTargetState.suspended
        : ReportTargetState.deleted;
  }
  if (target.isPublic == false) return ReportTargetState.private;
  return ReportTargetState.visible;
}

String reportTargetStateLabel(AppStrings strings, ReportTargetState state) =>
    switch (state) {
      ReportTargetState.visible => strings.targetStateVisible,
      ReportTargetState.private => strings.targetStatePrivate,
      ReportTargetState.deleted => strings.targetStateDeleted,
      ReportTargetState.suspended => strings.targetStateSuspended,
      ReportTargetState.unavailable => strings.targetStateUnavailable,
    };

/// Local date (with year) and time in the app language.
String formatModerationTime(BuildContext context, DateTime value) {
  final local = value.toLocal();
  final locale = Localizations.localeOf(context).toLanguageTag();
  final date = DateFormat.yMMMd(locale).format(local);
  final time = MaterialLocalizations.of(context).formatTimeOfDay(
    TimeOfDay.fromDateTime(local),
    alwaysUse24HourFormat:
        MediaQuery.maybeOf(context)?.alwaysUse24HourFormat ?? false,
  );
  return '$date, $time';
}

/// The content-removing action a report allows, when its target still exists.
class ModerationRemoval {
  const ModerationRemoval({
    required this.action,
    required this.isSuspension,
  });

  final String action;
  final bool isSuspension;
}

ModerationRemoval? removalFor(ReportData report) {
  if (reportTargetState(report)
      case ReportTargetState.deleted ||
          ReportTargetState.suspended ||
          ReportTargetState.unavailable) {
    return null;
  }
  return switch (report.targetType) {
    'post' ||
    'lost_pet' ||
    'adoption_post' =>
      const ModerationRemoval(action: 'soft_delete_post', isSuspension: false),
    'comment' => const ModerationRemoval(
        action: 'soft_delete_comment', isSuspension: false),
    'user' =>
      const ModerationRemoval(action: 'suspend_user', isSuspension: true),
    _ => null,
  };
}

/// App route of the reported content, for content that is still available.
String? reportedContentRoute(ReportData report) {
  if (reportTargetState(report)
      case ReportTargetState.deleted ||
          ReportTargetState.suspended ||
          ReportTargetState.unavailable) {
    return null;
  }
  final id = Uri.encodeComponent(report.targetId);
  switch (report.targetType) {
    case 'post':
      return '/posts/$id';
    case 'lost_pet':
      return '/lost-pets/$id';
    case 'adoption_post':
      return '/adoption-posts/$id';
    case 'user':
      return '/users/$id';
    case 'comment':
      // The API describes a comment's publication as "<kind>:<id>".
      final parent = report.target?.subtitle?.split(':');
      if (parent == null || parent.length != 2 || parent[1].isEmpty) {
        return null;
      }
      final parentId = Uri.encodeComponent(parent[1]);
      return switch (parent[0]) {
        'post' => '/posts/$parentId?comments=1',
        'lost_pet' => '/lost-pets/$parentId',
        'adoption_post' => '/adoption-posts/$parentId',
        _ => null,
      };
  }
  return null;
}
