import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/location/location_service.dart';
import '../../../core/theme/app_design_tokens.dart';
import '../../../core/widgets/app_surface.dart';
import '../../auth/application/auth_controller.dart';
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
  AlertPoint? _selectedPoint;
  DevicePushPermission _devicePermission = DevicePushPermission.unavailable;
  bool _loading = true;
  bool _loadFailed = false;
  bool _editingPoint = false;
  bool _locating = false;
  bool _permissionPromptShown = false;
  String? _savingField;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshDevicePermission());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _refreshDevicePermission() async {
    try {
      final status = await ref.read(devicePushAccessProvider).status();
      if (mounted) setState(() => _devicePermission = status);
    } catch (_) {
      if (mounted) {
        setState(() => _devicePermission = DevicePushPermission.unavailable);
      }
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final preferences = await ref.read(notificationApiProvider).preferences();
      if (!mounted) return;
      setState(() {
        _preferences = preferences;
        _selectedPoint = preferences.alertLocation;
      });
      await _refreshDevicePermission();
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String key) {
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(ref.read(notificationStringsProvider).get(key)),
      ));
  }

  Future<bool> _save(String field, Map<String, Object?> patch) async {
    if (_savingField != null) return false;
    setState(() => _savingField = field);
    try {
      final preferences =
          await ref.read(notificationApiProvider).updatePreferences(patch);
      if (!mounted) return false;
      setState(() {
        _preferences = preferences;
        _selectedPoint = preferences.alertLocation;
        if (field == 'nearby') _editingPoint = false;
      });
      return true;
    } catch (_) {
      if (mounted) _showError('save_failed');
      return false;
    } finally {
      if (mounted) setState(() => _savingField = null);
    }
  }

  Future<void> _requestPushPermission() async {
    if (_preferences?.pushAvailable != true ||
        (_devicePermission != DevicePushPermission.notDetermined &&
            _devicePermission != DevicePushPermission.denied)) {
      return;
    }
    _permissionPromptShown = true;
    final copy = ref.read(notificationStringsProvider);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: Text(copy.get('permission_context')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(copy.get('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(copy.get('allow')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final allowed =
          await ref.read(devicePushAccessProvider).requestPermission();
      await _refreshDevicePermission();
      if (!allowed || !mounted) return;
      final token = await AndroidPushService.token();
      final userId = ref.read(currentUserProvider)?.id;
      if (token != null && userId != null) {
        await AndroidPushService.register(
          ref.read(notificationApiProvider),
          userId,
          token,
        );
      }
    } catch (_) {
      if (mounted) _showError('permission_failed');
    }
  }

  Future<void> _maybeRequestPushPermission() async {
    if (_permissionPromptShown ||
        _devicePermission != DevicePushPermission.notDetermined ||
        _preferences?.pushAvailable != true) {
      return;
    }
    await _requestPushPermission();
  }

  Future<void> _openAndroidSettings() async {
    try {
      await ref.read(devicePushAccessProvider).openSettings();
    } catch (_) {
      if (mounted) _showError('settings_failed');
    }
  }

  Future<void> _setPushPreference(String field, bool value) async {
    if (await _save(field, {field: value}) && value) {
      await _maybeRequestPushPermission();
    }
  }

  Future<void> _useCurrentLocation() async {
    if (_locating || _savingField != null) return;
    setState(() => _locating = true);
    final location =
        await ref.read(locationServiceProvider).resolveCurrentLocation();
    if (!mounted) return;
    setState(() => _locating = false);
    if (location == null) {
      _showError('location_failed');
      return;
    }
    setState(() =>
        _selectedPoint = AlertPoint(location.latitude, location.longitude));
  }

  Future<void> _setNearby(bool enabled) async {
    if (!enabled) {
      await _save('nearby', {'nearby_enabled': false});
      return;
    }
    final point = _selectedPoint;
    if (point == null) {
      setState(() => _editingPoint = true);
      _showError('select_point');
      return;
    }
    if (await _save('nearby', {
      'alert_location': point.toJson(),
      'nearby_enabled': true,
    })) {
      await _maybeRequestPushPermission();
    }
  }

  Future<void> _savePoint() async {
    final point = _selectedPoint;
    if (point == null) {
      _showError('select_point');
      return;
    }
    if (_preferences?.nearbyEnabled == true) {
      await _save('nearby', {'alert_location': point.toJson()});
    } else {
      await _setNearby(true);
    }
  }

  Widget _sectionTitle(String title) => Padding(
        padding: const EdgeInsets.only(
          top: AppSpacing.xl,
          bottom: AppSpacing.sm,
        ),
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      );

  Widget _pushStatus(NotificationStrings copy, NotificationPreferences prefs) {
    final theme = Theme.of(context);
    final status = _devicePermission;
    final isWeb = status == DevicePushPermission.web;
    final unavailable =
        !prefs.pushAvailable || status == DevicePushPermission.unavailable;
    final allowed = status == DevicePushPermission.allowed && !unavailable;
    final permanent = status == DevicePushPermission.deniedPermanently;
    final title = isWeb
        ? copy.get('web_status')
        : unavailable
            ? copy.get('push_not_configured')
            : allowed
                ? copy.get('push_enabled')
                : copy.get('device_push_disabled');
    final message = isWeb
        ? copy.get('web_status_hint')
        : unavailable
            ? copy.get('push_not_configured_hint')
            : allowed
                ? copy.get('push_enabled_hint')
                : copy.get('device_push_disabled_hint');
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
              allowed
                  ? Icons.notifications_active_outlined
                  : Icons.notifications_off_outlined,
              color: theme.colorScheme.primary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleSmall),
              const SizedBox(height: AppSpacing.xs),
              Text(message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  )),
              if (!isWeb && !unavailable && !allowed) ...[
                const SizedBox(height: AppSpacing.sm),
                TextButton(
                  onPressed:
                      permanent ? _openAndroidSettings : _requestPushPermission,
                  child: Text(copy.get(permanent
                      ? 'open_android_settings'
                      : 'enable_notifications')),
                ),
              ],
            ],
          )),
        ],
      ),
    );
  }

  Widget _pointMap({required bool editable}) {
    final point = _selectedPoint;
    return SizedBox(
      height: editable ? 210 : 140,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: FlutterMap(
          key: ValueKey(
              'alert-map-$editable-${point?.latitude}-${point?.longitude}'),
          options: MapOptions(
            initialCenter: point == null
                ? const LatLng(41.3111, 69.2797)
                : LatLng(point.latitude, point.longitude),
            initialZoom: point == null ? 11 : 15,
            interactionOptions: InteractionOptions(
              flags: editable ? InteractiveFlag.all : InteractiveFlag.none,
            ),
            onTap: editable
                ? (_, position) {
                    setState(() => _selectedPoint =
                        AlertPoint(position.latitude, position.longitude));
                  }
                : null,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'mushukistan_frontend',
            ),
            if (point != null)
              MarkerLayer(markers: [
                Marker(
                  point: LatLng(point.latitude, point.longitude),
                  width: 40,
                  height: 40,
                  child: Icon(Icons.location_on,
                      size: 36, color: Theme.of(context).colorScheme.primary),
                ),
              ]),
            RichAttributionWidget(attributions: [
              TextSourceAttribution(
                'OpenStreetMap contributors',
                onTap: () => launchUrl(
                    Uri.parse('https://www.openstreetmap.org/copyright')),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _nearbySection(
      NotificationStrings copy, NotificationPreferences prefs) {
    final hasPoint = _selectedPoint != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(copy.get('nearby')),
          subtitle: Text(copy.get('nearby_hint')),
          value: prefs.nearbyEnabled,
          onChanged: _savingField != null ? null : _setNearby,
        ),
        if (_editingPoint) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(copy.get('map_guidance')),
          const SizedBox(height: AppSpacing.sm),
          _pointMap(editable: true),
          const SizedBox(height: AppSpacing.sm),
          Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
            TextButton.icon(
              onPressed: _locating || _savingField != null
                  ? null
                  : _useCurrentLocation,
              icon: const Icon(Icons.my_location),
              label: Text(copy.get('use_location')),
            ),
            TextButton(
              onPressed: _savingField != null
                  ? null
                  : () => setState(() {
                        _editingPoint = false;
                        _selectedPoint = prefs.alertLocation;
                      }),
              child: Text(copy.get('cancel')),
            ),
          ]),
        ] else if (hasPoint) ...[
          const SizedBox(height: AppSpacing.sm),
          _pointMap(editable: false),
          const SizedBox(height: AppSpacing.sm),
          TextButton.icon(
            onPressed: _savingField != null
                ? null
                : () => setState(() => _editingPoint = true),
            icon: const Icon(Icons.edit_location_alt_outlined),
            label: Text(copy.get('change_point')),
          ),
        ] else ...[
          const SizedBox(height: AppSpacing.sm),
          Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
            OutlinedButton.icon(
              onPressed: _locating || _savingField != null
                  ? null
                  : _useCurrentLocation,
              icon: const Icon(Icons.my_location),
              label: Text(copy.get('use_location')),
            ),
            OutlinedButton.icon(
              onPressed: _savingField != null
                  ? null
                  : () => setState(() => _editingPoint = true),
              icon: const Icon(Icons.map_outlined),
              label: Text(copy.get('choose_map')),
            ),
          ]),
        ],
        if (hasPoint && (!prefs.nearbyEnabled || _editingPoint)) ...[
          const SizedBox(height: AppSpacing.sm),
          FilledButton.icon(
            onPressed: _savingField != null ? null : _savePoint,
            icon: const Icon(Icons.check),
            label: Text(
                copy.get(prefs.nearbyEnabled ? 'save_point' : 'enable_nearby')),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final copy = ref.watch(notificationStringsProvider);
    final prefs = _preferences;
    return Scaffold(
      appBar: AppBar(centerTitle: true, title: Text(copy.get('settings'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadFailed || prefs == null
              ? AppStatePanel(
                  icon: Icons.notifications_off_outlined,
                  title: copy.get('error'),
                  action: TextButton(
                    onPressed: _load,
                    child: Text(copy.get('retry')),
                  ),
                )
              : AppContentWidth(
                  maxWidth: AppWidths.compact,
                  child: ListView(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    children: [
                      _pushStatus(copy, prefs),
                      _sectionTitle(copy.get('activity_section')),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(copy.get('push_comments')),
                        value: prefs.pushComments,
                        onChanged: _savingField != null
                            ? null
                            : (value) =>
                                _setPushPreference('push_comments', value),
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(copy.get('push_replies')),
                        value: prefs.pushReplies,
                        onChanged: _savingField != null
                            ? null
                            : (value) =>
                                _setPushPreference('push_replies', value),
                      ),
                      _sectionTitle(copy.get('pets_section')),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(copy.get('push_followups')),
                        value: prefs.pushFollowups,
                        onChanged: _savingField != null
                            ? null
                            : (value) =>
                                _setPushPreference('push_followups', value),
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(copy.get('inactivity')),
                        subtitle: Text(copy.get('inactivity_hint')),
                        value: prefs.inactivityEnabled,
                        onChanged: _savingField != null
                            ? null
                            : (value) =>
                                _setPushPreference('inactivity_enabled', value),
                      ),
                      _sectionTitle(copy.get('nearby_section')),
                      _nearbySection(copy, prefs),
                      const SizedBox(height: AppSpacing.xxl),
                    ],
                  ),
                ),
    );
  }
}
