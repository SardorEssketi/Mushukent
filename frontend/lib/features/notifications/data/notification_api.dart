import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

final notificationApiProvider = Provider<NotificationApi>((ref) {
  return NotificationApi(ref.watch(apiClientProvider));
});

class NotificationApi {
  const NotificationApi(this._client);

  final MushukistanApiClient _client;

  Future<NotificationPage> list({String? cursor}) =>
      _client.get<NotificationPage>(
        'notifications',
        queryParameters: {if (cursor != null) 'cursor': cursor},
        decoder: NotificationPage.fromJson,
      );

  Future<int> unreadCount() => _client.get<int>(
        'notifications/unread-count',
        decoder: (json) => (json as Map)['count'] as int,
      );

  Future<void> markRead(String id) => _client.postJson<void>(
        'notifications/$id/read',
        decoder: (_) {},
      );

  Future<void> markAllRead() => _client.postJson<void>(
        'notifications/read-all',
        decoder: (_) {},
      );

  Future<NotificationPreferences> preferences() =>
      _client.get<NotificationPreferences>(
        'notifications/preferences',
        decoder: NotificationPreferences.fromJson,
      );

  Future<NotificationPreferences> updatePreferences(
          Map<String, Object?> patch) =>
      _client.patchJson<NotificationPreferences>(
        'notifications/preferences',
        body: patch,
        decoder: NotificationPreferences.fromJson,
      );

  Future<void> recordActivity() => _client.postJson<void>(
        'notifications/activity',
        decoder: (_) {},
      );

  Future<void> registerToken(String token, {String? previousToken}) =>
      _client.postJson<void>(
        'notifications/devices',
        body: {
          'platform': 'android',
          'token': token,
          if (previousToken != null) 'previous_token': previousToken,
        },
        decoder: (_) {},
      );

  Future<void> unregisterToken(String token) => _client.postJson<void>(
        'notifications/devices/unregister',
        body: {'platform': 'android', 'token': token},
        decoder: (_) {},
      );
}

class NotificationEntry {
  const NotificationEntry({
    required this.id,
    required this.kind,
    required this.targetKind,
    required this.targetId,
    required this.createdAt,
    this.commentId,
    this.actorName,
    this.readAt,
  });

  final String id;
  final String kind;
  final String targetKind;
  final String targetId;
  final String? commentId;
  final String? actorName;
  final DateTime createdAt;
  final DateTime? readAt;

  factory NotificationEntry.fromJson(Object? json) {
    final map = json as Map;
    return NotificationEntry(
      id: map['id'] as String,
      kind: map['kind'] as String,
      targetKind: map['target_kind'] as String,
      targetId: map['target_id'] as String,
      commentId: map['comment_id'] as String?,
      actorName: map['actor_name'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      readAt: map['read_at'] == null
          ? null
          : DateTime.parse(map['read_at'] as String),
    );
  }
}

class NotificationPage {
  const NotificationPage(this.items, this.nextCursor);

  final List<NotificationEntry> items;
  final String? nextCursor;

  factory NotificationPage.fromJson(Object? json) {
    final map = json as Map;
    return NotificationPage(
      (map['items'] as List).map(NotificationEntry.fromJson).toList(),
      map['next_cursor'] as String?,
    );
  }
}

class AlertPoint {
  const AlertPoint(this.latitude, this.longitude);
  final double latitude;
  final double longitude;

  factory AlertPoint.fromJson(Object? json) {
    final map = json as Map;
    return AlertPoint(
      (map['latitude'] as num).toDouble(),
      (map['longitude'] as num).toDouble(),
    );
  }

  Map<String, Object?> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
      };
}

class NotificationPreferences {
  const NotificationPreferences({
    required this.pushComments,
    required this.pushReplies,
    required this.pushFollowups,
    required this.nearbyEnabled,
    required this.inactivityEnabled,
    required this.pushAvailable,
    this.alertLocation,
  });

  final bool pushComments;
  final bool pushReplies;
  final bool pushFollowups;
  final bool nearbyEnabled;
  final bool inactivityEnabled;
  final bool pushAvailable;
  final AlertPoint? alertLocation;

  factory NotificationPreferences.fromJson(Object? json) {
    final map = json as Map;
    return NotificationPreferences(
      pushComments: map['push_comments'] as bool,
      pushReplies: map['push_replies'] as bool,
      pushFollowups: map['push_followups'] as bool,
      nearbyEnabled: map['nearby_enabled'] as bool,
      inactivityEnabled: map['inactivity_enabled'] as bool,
      pushAvailable: map['push_available'] as bool,
      alertLocation: map['alert_location'] == null
          ? null
          : AlertPoint.fromJson(map['alert_location']),
    );
  }
}

final unreadNotificationCountProvider = FutureProvider<int>((ref) {
  return ref.watch(notificationApiProvider).unreadCount();
});
