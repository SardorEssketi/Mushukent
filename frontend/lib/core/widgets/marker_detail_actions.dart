import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../localization/app_strings.dart';
import '../network/mushukistan_api.dart';
import '../validation/phone_numbers.dart';

enum MapDirectionsProvider { googleMaps, yandexMaps }

bool hasValidMapCoordinates(GeoPoint? destination) {
  if (destination == null) {
    return false;
  }
  return destination.latitude.isFinite &&
      destination.longitude.isFinite &&
      destination.latitude >= -90 &&
      destination.latitude <= 90 &&
      destination.longitude >= -180 &&
      destination.longitude <= 180;
}

Uri googleMapsWebRouteUri(GeoPoint destination) {
  _validateCoordinates(destination);
  return Uri.https(
    'www.google.com',
    '/maps/dir/',
    <String, String>{
      'api': '1',
      'destination': _coordinatePair(destination),
      'travelmode': 'driving',
    },
  );
}

Uri googleMapsAndroidRouteUri(GeoPoint destination) {
  _validateCoordinates(destination);
  return Uri.parse(
    'google.navigation:q=${_coordinatePair(destination)}&mode=d',
  );
}

Uri googleMapsIosRouteUri(GeoPoint destination) {
  _validateCoordinates(destination);
  return Uri.parse(
    'comgooglemaps://?daddr=${_coordinatePair(destination)}'
    '&directionsmode=driving',
  );
}

Uri yandexMapsWebRouteUri(GeoPoint destination) {
  _validateCoordinates(destination);
  return Uri.https(
    'yandex.com',
    '/maps/',
    <String, String>{
      'rtext': '~${_coordinatePair(destination)}',
      'rtt': 'auto',
    },
  );
}

Uri yandexMapsNativeRouteUri(GeoPoint destination) {
  _validateCoordinates(destination);
  return Uri.parse(
    'yandexmaps://maps.yandex.com/?rtext=~${_coordinatePair(destination)}'
    '&rtt=auto',
  );
}

Future<void> showDirectionsChooser(
  BuildContext context, {
  required GeoPoint destination,
  required AppStrings strings,
}) async {
  if (!hasValidMapCoordinates(destination)) {
    return;
  }

  final provider = await showModalBottomSheet<MapDirectionsProvider>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.map_outlined),
              title: Text(strings.googleMaps),
              onTap: () => Navigator.of(sheetContext).pop(
                MapDirectionsProvider.googleMaps,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.explore_outlined),
              title: Text(strings.yandexMaps),
              onTap: () => Navigator.of(sheetContext).pop(
                MapDirectionsProvider.yandexMaps,
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );

  if (provider == null || !context.mounted) {
    return;
  }

  final launched = await launchDirections(provider, destination);
  if (!launched && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(strings.couldNotOpenDirections)),
    );
  }
}

Future<bool> launchDirections(
  MapDirectionsProvider provider,
  GeoPoint destination,
) async {
  if (!hasValidMapCoordinates(destination)) {
    return false;
  }

  final fallback = switch (provider) {
    MapDirectionsProvider.googleMaps => googleMapsWebRouteUri(destination),
    MapDirectionsProvider.yandexMaps => yandexMapsWebRouteUri(destination),
  };
  final native = switch (provider) {
    MapDirectionsProvider.googleMaps => _googleNativeRouteUri(destination),
    MapDirectionsProvider.yandexMaps => _yandexNativeRouteUri(destination),
  };
  final primary = native ?? fallback;

  if (await launchUrl(primary, mode: LaunchMode.externalApplication)) {
    return true;
  }
  if (primary == fallback) {
    return false;
  }
  return launchUrl(fallback, mode: LaunchMode.externalApplication);
}

Future<void> launchPublicPhone(
  BuildContext context, {
  required String phone,
  required AppStrings strings,
}) async {
  final uri = publicPhoneUri(phone);
  if (uri == null) {
    return;
  }
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
      context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(strings.couldNotOpenPhone)),
    );
  }
}

class MarkerDetailActions extends StatelessWidget {
  const MarkerDetailActions({
    super.key,
    required this.strings,
    this.destination,
    this.publicPhone,
    this.showRoute = true,
  });

  final AppStrings strings;
  final GeoPoint? destination;
  final String? publicPhone;
  final bool showRoute;

  @override
  Widget build(BuildContext context) {
    final hasDestination = showRoute && hasValidMapCoordinates(destination);
    final hasPhone = publicPhoneUri(publicPhone) != null;
    if (!hasDestination && !hasPhone) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        if (hasDestination)
          FilledButton.tonalIcon(
            onPressed: () => unawaited(
              showDirectionsChooser(
                context,
                destination: destination!,
                strings: strings,
              ),
            ),
            icon: const Icon(Icons.directions_outlined),
            label: Text(strings.route),
          ),
        if (hasPhone)
          OutlinedButton.icon(
            onPressed: () => unawaited(
              launchPublicPhone(
                context,
                phone: publicPhone!,
                strings: strings,
              ),
            ),
            icon: const Icon(Icons.call_outlined),
            label: Text(strings.call),
          ),
      ],
    );
  }
}

Uri? _googleNativeRouteUri(GeoPoint destination) {
  if (kIsWeb) {
    return null;
  }
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => googleMapsAndroidRouteUri(destination),
    TargetPlatform.iOS => googleMapsIosRouteUri(destination),
    _ => null,
  };
}

Uri? _yandexNativeRouteUri(GeoPoint destination) {
  if (kIsWeb) {
    return null;
  }
  return switch (defaultTargetPlatform) {
    TargetPlatform.android ||
    TargetPlatform.iOS =>
      yandexMapsNativeRouteUri(destination),
    _ => null,
  };
}

String _coordinatePair(GeoPoint destination) {
  return '${destination.latitude},${destination.longitude}';
}

void _validateCoordinates(GeoPoint destination) {
  if (!hasValidMapCoordinates(destination)) {
    throw ArgumentError.value(
        destination, 'destination', 'Invalid coordinates');
  }
}
