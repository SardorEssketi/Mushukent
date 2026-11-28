import 'package:flutter/material.dart';

import 'notification_strings.dart';

/// The location disclosure shown before nearby alerts are turned on (from the
/// notification settings switch or the one-time prompt).
Future<bool?> discloseNearbyAlerts(
        BuildContext context, NotificationStrings copy) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(copy.get('nearby')),
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
