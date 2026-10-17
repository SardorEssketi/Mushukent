import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/location/location_service.dart';
import '../../../core/theme/app_design_tokens.dart';
import '../../../core/widgets/app_surface.dart';
import '../application/nearby_alerts.dart';
import '../application/notification_push.dart';
import '../data/notification_api.dart';
import 'notification_strings.dart';

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
  AuthorizedLocationStatus _location = AuthorizedLocationStatus.unsupported;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final preferences = await ref.read(notificationApiProvider).preferences();
      final permission = await ref.read(devicePushAccessProvider).status();
      final location = ref.read(nearbyAlertsAndroidProvider)
          ? await ref.read(locationServiceProvider).authorizedStatus()
          : AuthorizedLocationStatus.unsupported;
      if (!mounted) return;
      setState(() {
        _preferences = preferences;
        _permission = permission;
        _location = location;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                ref.read(notificationStringsProvider).get('settings_failed'))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = ref.watch(notificationStringsProvider);
    final nearby = ref.watch(nearbyAlertsProvider);
    final android = ref.watch(nearbyAlertsAndroidProvider);
    final pushAvailable = _preferences?.pushAvailable == true &&
        ref.read(devicePushAccessProvider).available;
    final permitted = _permission == DevicePushPermission.allowed;
    final nearbyAvailable = android &&
        _location == AuthorizedLocationStatus.authorized &&
        nearby.status == NearbyAlertStatus.available;
    return Scaffold(
      appBar: AppBar(title: Text(copy.get('title'))),
      body: AppContentWidth(
          maxWidth: AppWidths.compact,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _failed
                    ? Column(children: [
                        Text(copy.get('error')),
                        TextButton(
                            onPressed: _load, child: Text(copy.get('retry'))),
                      ])
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                            Text(copy.get('automatic_hint')),
                            const SizedBox(height: AppSpacing.lg),
                            AppCard(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  _row(
                                      Icons.notifications_outlined,
                                      copy.get('permission_status'),
                                      copy.get(!android
                                          ? 'android_only'
                                          : permitted
                                              ? 'permission_allowed'
                                              : 'permission_denied')),
                                  if (android && !permitted)
                                    TextButton(
                                        onPressed: _openSettings,
                                        child: Text(
                                            copy.get('open_android_settings'))),
                                  const Divider(),
                                  _row(
                                      Icons.send_outlined,
                                      copy.get('push_status'),
                                      copy.get(pushAvailable && permitted
                                          ? 'push_available'
                                          : 'push_unavailable')),
                                  const Divider(),
                                  _row(
                                      Icons.location_on_outlined,
                                      copy.get('nearby'),
                                      copy.get(nearbyAvailable
                                          ? 'nearby_available'
                                          : !android
                                              ? 'android_only'
                                              : _location !=
                                                      AuthorizedLocationStatus
                                                          .authorized
                                                  ? 'nearby_permission_missing'
                                                  : nearby.status ==
                                                          NearbyAlertStatus
                                                              .consentRequired
                                                      ? 'nearby_consent_missing'
                                                      : nearby.status ==
                                                              NearbyAlertStatus
                                                                  .syncFailed
                                                          ? 'sync_failed'
                                                          : 'nearby_unavailable')),
                                  if (android &&
                                      (_location ==
                                              AuthorizedLocationStatus.denied ||
                                          _location ==
                                              AuthorizedLocationStatus
                                                  .deniedForever))
                                    TextButton(
                                        onPressed: () =>
                                            _openSettings(location: true),
                                        child: Text(copy
                                            .get('open_location_settings'))),
                                ])),
                            const SizedBox(height: AppSpacing.lg),
                            Text(copy.get('inbox_hint')),
                            const SizedBox(height: AppSpacing.md),
                            Text(copy.get('nearby_disclosure')),
                          ]),
          )),
    );
  }

  Widget _row(IconData icon, String title, String status) => ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(status));

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
