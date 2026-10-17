import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/mushukistan_api.dart';
import '../../notifications/data/notification_api.dart';

/// Refreshes everything whose contents depend on the viewer's block list.
///
/// Blocking is enforced by the server, so after a block or unblock every list that was
/// loaded under the old relationship (feed, map, post/profile views, user activity) must be
/// reloaded: bumping [postMutationRevisionProvider] makes those providers refetch, and the
/// unread badge is refreshed because blocked senders' notifications are hidden.
void refreshAfterBlockChange(WidgetRef ref) {
  ref.read(postMutationRevisionProvider.notifier).state++;
  ref.invalidate(unreadNotificationCountProvider);
}
