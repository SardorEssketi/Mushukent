import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/location/location_service.dart';
import '../../auth/application/auth_controller.dart';
import '../../../core/widgets/app_surface.dart';
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
    extends ConsumerState<NotificationSettingsScreen> {
  NotificationPreferences? _preferences;
  AlertPoint? _selectedPoint;
  bool _loading = true;
  bool _saving = false;
  bool _permissionGranted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final prefs = await ref.read(notificationApiProvider).preferences();
      final permission = await AndroidPushService.authorized();
      if (mounted) {
        setState(() {
          _preferences = prefs;
          _selectedPoint = prefs.alertLocation;
          _permissionGranted = permission;
        });
      }
    } catch (_) {
      if (mounted) _error();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _error() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content:
              Text(ref.read(notificationStringsProvider).get('save_failed'))),
    );
  }

  Future<void> _save(Map<String, Object?> patch) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final prefs =
          await ref.read(notificationApiProvider).updatePreferences(patch);
      if (mounted) {
        setState(() {
          _preferences = prefs;
          _selectedPoint = prefs.alertLocation;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(ref.read(notificationStringsProvider).get('saved'))),
        );
      }
    } catch (_) {
      if (mounted) _error();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _requestPushPermission() async {
    final copy = ref.read(notificationStringsProvider);
    if (!AndroidPushConfiguration.ready) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(copy.get('permission_context')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(copy.get('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(copy.get('allow'))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final allowed = await AndroidPushService.requestPermission();
      if (!mounted) return;
      setState(() => _permissionGranted = allowed);
      if (allowed) {
        final token = await AndroidPushService.token();
        if (token != null) {
          final userId = ref.read(currentUserProvider)?.id;
          if (userId != null) {
            await AndroidPushService.register(
              ref.read(notificationApiProvider),
              userId,
              token,
            );
          }
        }
      }
    } catch (_) {
      if (mounted) _error();
    }
  }

  Future<void> _useCurrentLocation() async {
    final location = await LocationService().resolveCurrentLocation();
    if (!mounted) return;
    if (location == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                ref.read(notificationStringsProvider).get('location_failed'))),
      );
      return;
    }
    setState(() =>
        _selectedPoint = AlertPoint(location.latitude, location.longitude));
  }

  Future<void> _enableNearby() async {
    final point = _selectedPoint;
    if (point == null) return;
    await _save({'alert_location': point.toJson(), 'nearby_enabled': true});
    if (mounted &&
        _preferences?.nearbyEnabled == true &&
        _preferences?.pushAvailable == true &&
        AndroidPushConfiguration.ready &&
        !_permissionGranted) {
      await _requestPushPermission();
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = ref.watch(notificationStringsProvider);
    final prefs = _preferences;
    final pushUsable = _permissionGranted &&
        AndroidPushConfiguration.ready &&
        (prefs?.pushAvailable ?? false);
    return Scaffold(
      appBar: AppBar(title: Text(copy.get('settings'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : prefs == null
              ? Center(
                  child: TextButton(
                      onPressed: _load, child: Text(copy.get('error'))))
              : AppContentWidth(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (!pushUsable) ...[
                        Text(copy.get('push_unavailable')),
                        if (AndroidPushConfiguration.ready &&
                            prefs.pushAvailable &&
                            !_permissionGranted)
                          TextButton(
                            onPressed: _requestPushPermission,
                            child: Text(copy.get('allow')),
                          ),
                      ],
                      SwitchListTile(
                        title: Text(copy.get('push_comments')),
                        value: prefs.pushComments,
                        onChanged: _saving || !pushUsable
                            ? null
                            : (value) => _save({'push_comments': value}),
                      ),
                      SwitchListTile(
                        title: Text(copy.get('push_replies')),
                        value: prefs.pushReplies,
                        onChanged: _saving || !pushUsable
                            ? null
                            : (value) => _save({'push_replies': value}),
                      ),
                      SwitchListTile(
                        title: Text(copy.get('push_followups')),
                        value: prefs.pushFollowups,
                        onChanged: _saving || !pushUsable
                            ? null
                            : (value) => _save({'push_followups': value}),
                      ),
                      SwitchListTile(
                        title: Text(copy.get('inactivity')),
                        subtitle: Text(copy.get('inactivity_hint')),
                        value: prefs.inactivityEnabled,
                        onChanged: _saving || !pushUsable
                            ? null
                            : (value) => _save({'inactivity_enabled': value}),
                      ),
                      const Divider(),
                      Text(copy.get('nearby_hint')),
                      const SizedBox(height: 12),
                      Text(copy.get('choose_point')),
                      SizedBox(
                        height: 260,
                        child: FlutterMap(
                          key: ValueKey(_selectedPoint?.latitude),
                          options: MapOptions(
                            initialCenter: _selectedPoint == null
                                ? const LatLng(41.3111, 69.2797)
                                : LatLng(_selectedPoint!.latitude,
                                    _selectedPoint!.longitude),
                            initialZoom: 13,
                            onTap: (_, point) => setState(() => _selectedPoint =
                                AlertPoint(point.latitude, point.longitude)),
                          ),
                          children: [
                            TileLayer(
                              urlTemplate:
                                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'mushukistan_frontend',
                            ),
                            if (_selectedPoint != null)
                              MarkerLayer(markers: [
                                Marker(
                                  point: LatLng(_selectedPoint!.latitude,
                                      _selectedPoint!.longitude),
                                  width: 40,
                                  height: 40,
                                  child:
                                      const Icon(Icons.location_on, size: 36),
                                ),
                              ]),
                            RichAttributionWidget(attributions: [
                              TextSourceAttribution(
                                'OpenStreetMap contributors',
                                onTap: () => launchUrl(Uri.parse(
                                    'https://www.openstreetmap.org/copyright')),
                              ),
                            ]),
                          ],
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _useCurrentLocation,
                        icon: const Icon(Icons.my_location),
                        label: Text(copy.get('use_location')),
                      ),
                      FilledButton(
                        onPressed: _saving || _selectedPoint == null
                            ? null
                            : _enableNearby,
                        child: Text(copy.get('save_point')),
                      ),
                      if (prefs.nearbyEnabled || prefs.alertLocation != null)
                        TextButton(
                          onPressed: _saving
                              ? null
                              : () => _save({'nearby_enabled': false}),
                          child: Text(copy.get('disable_nearby')),
                        ),
                    ],
                  ),
                ),
    );
  }
}
