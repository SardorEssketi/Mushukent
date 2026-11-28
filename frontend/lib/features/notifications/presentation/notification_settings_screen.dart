import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/location/location_service.dart';
import '../../../core/theme/app_design_tokens.dart';
import '../../../core/widgets/app_surface.dart';
import '../../auth/application/auth_controller.dart';
import '../application/nearby_alerts.dart';
import '../application/notification_push.dart';
import '../data/notification_api.dart';
import 'nearby_alert_privacy.dart';
import 'notification_strings.dart';

/// Android notification settings: one switch per kind of notification, each
/// saved at once (docs/UI_UX.md, Notifications). Not shown on other platforms.
class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});
  @override
  ConsumerState<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends ConsumerState<NotificationSettingsScreen>
    with WidgetsBindingObserver {
  NotificationPreferences? _preferences;
  DevicePushPermission _permission = DevicePushPermission.unavailable;
  bool _loading = true;
  bool _failed = false;

  /// Switches with a request in flight; they ignore taps until it settles.
  final _saving = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from Android settings: the permission may have changed.
    if (state == AppLifecycleState.resumed) unawaited(_load(quiet: true));
  }

  Future<void> _load({bool quiet = false}) async {
    if (!mounted) return;
    if (!quiet) {
      setState(() {
        _loading = true;
        _failed = false;
      });
    }
    try {
      final preferences = await ref.read(notificationApiProvider).preferences();
      final permission = await ref.read(devicePushAccessProvider).status();
      if (!mounted) return;
      setState(() {
        _preferences = preferences;
        _permission = permission;
        _failed = false;
      });
    } catch (_) {
      if (mounted && !quiet) setState(() => _failed = true);
    } finally {
      if (mounted && !quiet) setState(() => _loading = false);
    }
  }

  /// First tap asks in-app (once per account); afterwards, or once Android
  /// blocks the prompt, it opens the system notification settings.
  Future<void> _enableNotifications() async {
    if (await askForNotificationsOnce(context, ref, includeNearby: false)) {
      await _load(quiet: true);
      return;
    }
    await _openSettings();
  }

  Future<void> _openSettings({bool location = false}) async {
    try {
      if (location) {
        if (!await ref.read(locationServiceProvider).openSettings()) {
          throw StateError('Settings unavailable');
        }
      } else {
        await ref.read(devicePushAccessProvider).openSettings();
      }
    } catch (_) {
      _message(ref.read(notificationStringsProvider).get('settings_failed'));
    }
  }

  void _message(String text, {SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), action: action));
  }

  /// Shows [value] at once and saves it; on failure only this switch goes back.
  Future<void> _setCategory(String field, bool value) async {
    final current = _preferences;
    if (current == null || _saving.contains(field)) return;
    setState(() {
      _saving.add(field);
      _preferences = current.withSwitch(field, value);
    });
    try {
      final user = ref.read(currentUserProvider)?.id;
      final saved = await ref.read(notificationApiProvider).updatePreferences({
        field: value,
        if (user != null) 'expected_user_id': user,
      });
      if (mounted) {
        setState(() => _preferences =
            _preferences?.withSwitch(field, saved.switchValue(field)));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _preferences = _preferences?.withSwitch(field, !value));
        _message(ref.read(notificationStringsProvider).get('save_failed'));
      }
    } finally {
      if (mounted) setState(() => _saving.remove(field));
    }
  }

  /// On: disclosure, then location permission, then consent and the first
  /// private point. Off: withdraws consent, which deletes the stored point.
  Future<void> _setNearby(bool value) async {
    const field = 'nearby_enabled';
    final user = ref.read(currentUserProvider)?.id;
    if (user == null || _saving.contains(field)) return;
    final copy = ref.read(notificationStringsProvider);
    final nearby = ref.read(nearbyAlertsProvider);
    setState(() => _saving.add(field));
    try {
      if (value) {
        final agreed = await discloseNearbyAlerts(context, copy);
        if (agreed != true || !mounted) return;
        final location =
            await ref.read(locationServiceProvider).requestAuthorization();
        if (!mounted) return;
        if (location != AuthorizedLocationStatus.authorized) {
          _message(
            copy.get('nearby_permission_denied'),
            action: SnackBarAction(
              label: copy.get('open_location_settings'),
              onPressed: () => unawaited(_openSettings(location: true)),
            ),
          );
          return;
        }
      } else {
        setState(() => _preferences = _preferences?.withSwitch(field, false));
      }
      await nearby.setConsent(user, value);
      if (!mounted) return;
      if (nearby.status == NearbyAlertStatus.syncFailed) {
        _message(copy.get('sync_failed'));
      }
      await _load(quiet: true);
    } finally {
      if (mounted) setState(() => _saving.remove(field));
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = ref.watch(notificationStringsProvider);
    final preferences = _preferences;
    return Scaffold(
      appBar: AppBar(title: Text(copy.get('title'))),
      body: AppContentWidth(
        maxWidth: AppWidths.compact,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _failed || preferences == null
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(copy.get('error')),
                      TextButton(
                          onPressed: _load, child: Text(copy.get('retry'))),
                    ]),
                  )
                : ListView(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    children: [
                      ..._status(copy, preferences),
                      AppCard(
                        padding: EdgeInsets.zero,
                        child: Column(children: [
                          _switch(copy, preferences, 'push_comments',
                              Icons.mode_comment_outlined, 'pref_comments'),
                          _switch(copy, preferences, 'push_replies',
                              Icons.reply_outlined, 'pref_replies'),
                          _switch(copy, preferences, 'push_followups',
                              Icons.campaign_outlined, 'pref_followups',
                              subtitle: 'pref_followups_hint'),
                          _switch(copy, preferences, 'nearby_enabled',
                              Icons.location_on_outlined, 'nearby',
                              subtitle: 'nearby_hint', onChanged: _setNearby),
                          _switch(copy, preferences, 'inactivity_enabled',
                              Icons.schedule_outlined, 'pref_inactivity'),
                        ]),
                      ),
                    ],
                  ),
      ),
    );
  }

  /// Banner when Android notifications are off; a plain warning when they are
  /// allowed but push cannot be delivered.
  List<Widget> _status(
      NotificationStrings copy, NotificationPreferences prefs) {
    final colors = Theme.of(context).colorScheme;
    final permitted = _permission == DevicePushPermission.allowed;
    if (!permitted) {
      return [
        Container(
          key: const ValueKey('notifications-off-banner'),
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: colors.errorContainer,
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          child: Row(children: [
            Icon(Icons.notifications_off_outlined,
                color: colors.onErrorContainer),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(copy.get('push_off_banner'),
                  style: TextStyle(color: colors.onErrorContainer)),
            ),
            const SizedBox(width: AppSpacing.sm),
            FilledButton(
              onPressed: _enableNotifications,
              child: Text(copy.get('enable')),
            ),
          ]),
        ),
        const SizedBox(height: AppSpacing.lg),
      ];
    }
    final delivered =
        prefs.pushAvailable && ref.read(devicePushAccessProvider).available;
    if (delivered) return const [];
    return [
      Row(
        key: const ValueKey('push-unavailable-warning'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: colors.onSurfaceVariant),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(copy.get('push_unavailable_warning'),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: colors.onSurfaceVariant)),
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.lg),
    ];
  }

  Widget _switch(
    NotificationStrings copy,
    NotificationPreferences preferences,
    String field,
    IconData icon,
    String title, {
    String? subtitle,
    Future<void> Function(bool value)? onChanged,
  }) {
    final saving = _saving.contains(field);
    return SwitchListTile(
      key: ValueKey('notification-switch-$field'),
      secondary: Icon(icon),
      title: Text(copy.get(title)),
      subtitle: subtitle == null ? null : Text(copy.get(subtitle)),
      value: preferences.switchValue(field),
      onChanged: saving
          ? null
          : (value) =>
              unawaited((onChanged ?? (v) => _setCategory(field, v))(value)),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
