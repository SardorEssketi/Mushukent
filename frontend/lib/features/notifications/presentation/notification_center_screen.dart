import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/mushukistan_api.dart';
import '../data/notification_api.dart';
import 'notification_strings.dart';

String? notificationTargetPath(String kind, String id) {
  if (!RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(id)) return null;
  return switch (kind) {
    'post' => '/posts/$id',
    'lost_pet' => '/lost-pets/$id',
    'adoption_post' => '/adoption-posts/$id',
    _ => null,
  };
}

class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadNotificationCountProvider).valueOrNull ?? 0;
    return IconButton(
      tooltip: ref.watch(notificationStringsProvider).get('title'),
      onPressed: () => context.push('/notifications'),
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text(unread > 99 ? '99+' : '$unread'),
        child: const Icon(Icons.notifications_outlined),
      ),
    );
  }
}

class NotificationCenterScreen extends ConsumerStatefulWidget {
  const NotificationCenterScreen({super.key});

  @override
  ConsumerState<NotificationCenterScreen> createState() =>
      _NotificationCenterScreenState();
}

class _NotificationCenterScreenState
    extends ConsumerState<NotificationCenterScreen> {
  final List<NotificationEntry> _items = [];
  String? _cursor;
  bool _loading = false;
  bool _loaded = false;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    if (reset) {
      _items.clear();
      _cursor = null;
      _loaded = false;
    }
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final page =
          await ref.read(notificationApiProvider).list(cursor: _cursor);
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _cursor = page.nextCursor;
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _error = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(NotificationEntry entry) async {
    final api = ref.read(notificationApiProvider);
    try {
      await api.markRead(entry.id);
      ref.invalidate(unreadNotificationCountProvider);
      final index = _items.indexOf(entry);
      if (index >= 0 && mounted) {
        setState(() => _items[index] = NotificationEntry(
              id: entry.id,
              kind: entry.kind,
              targetKind: entry.targetKind,
              targetId: entry.targetId,
              commentId: entry.commentId,
              actorName: entry.actorName,
              createdAt: entry.createdAt,
              readAt: DateTime.now(),
            ));
      }
    } catch (_) {
      // Navigation can still work if marking read is temporarily unavailable.
    }
    final path = notificationTargetPath(entry.targetKind, entry.targetId);
    if (path == null) return;
    final destination = entry.kind == 'comment' || entry.kind == 'reply'
        ? '$path?comments=1'
        : path;
    try {
      final content = ref.read(mushukistanApiProvider);
      switch (entry.targetKind) {
        case 'post':
          await content.getPost(entry.targetId);
        case 'lost_pet':
          await content.getLostPet(entry.targetId);
        case 'adoption_post':
          await content.getAdoptionPost(entry.targetId);
      }
      if (mounted) context.push(destination);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  ref.read(notificationStringsProvider).get('unavailable'))),
        );
      }
    }
  }

  Future<void> _markAll() async {
    try {
      await ref.read(notificationApiProvider).markAllRead();
      ref.invalidate(unreadNotificationCountProvider);
      await _load(reset: true);
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = ref.watch(notificationStringsProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(copy.get('title')),
        actions: [
          IconButton(
            tooltip: copy.get('settings'),
            onPressed: () => context.push('/notifications/settings'),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: ListView(
          children: [
            if (_items.any((item) => item.readAt == null))
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _markAll,
                  child: Text(copy.get('mark_all')),
                ),
              ),
            for (final entry in _items)
              ListTile(
                leading: Icon(
                  entry.kind == 'nearby_lost_pet'
                      ? Icons.pets_outlined
                      : Icons.chat_bubble_outline,
                ),
                title: Text(
                  copy.forEntry(entry),
                  style: entry.readAt == null
                      ? const TextStyle(fontWeight: FontWeight.bold)
                      : null,
                ),
                subtitle: Text(
                  '${MaterialLocalizations.of(context).formatMediumDate(entry.createdAt.toLocal())} '
                  '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(entry.createdAt.toLocal()))}',
                ),
                trailing: entry.readAt == null
                    ? const Icon(Icons.circle, size: 9)
                    : null,
                onTap: () => _open(entry),
              ),
            if (_loaded && _items.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Center(child: Text(copy.get('empty'))),
              ),
            if (_error)
              Center(
                child: TextButton(
                  onPressed: _load,
                  child: Text(copy.get('error')),
                ),
              ),
            if (_loading) const Center(child: CircularProgressIndicator()),
            if (_cursor != null && !_loading)
              Center(
                child: TextButton(
                  onPressed: _load,
                  child: Text(copy.get('load_more')),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
