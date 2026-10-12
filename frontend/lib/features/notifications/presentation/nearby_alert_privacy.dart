import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../application/nearby_alerts.dart';
import 'notification_strings.dart';

Future<bool?> discloseNearbyAlerts(
        BuildContext context, NotificationStrings copy) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(copy.get('location_privacy')),
        content: Text(copy.get('nearby_disclosure')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(copy.get('consent_decline'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(copy.get('consent_allow'))),
        ],
      ),
    );

/// Privacy consent is separate from the read-only notification status screen.
Future<void> manageNearbyPrivacy(BuildContext context, WidgetRef ref) async {
  final user = ref.read(currentUserProvider)?.id;
  if (user == null) return;
  final controller = ref.read(nearbyAlertsProvider);
  final copy = ref.read(notificationStringsProvider);
  final granted = await discloseNearbyAlerts(context, copy);
  if (granted == null) return;
  if (!context.mounted || ref.read(currentUserProvider)?.id != user) return;
  await controller.setConsent(user, granted);
  if (context.mounted && controller.status == NearbyAlertStatus.syncFailed) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(copy.get('sync_failed'))));
  }
}
