import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/location/location_service.dart';
import '../../../../core/network/mushukistan_api.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../application/add_observation_controller.dart';

class AddObservationLocationScreen extends ConsumerStatefulWidget {
  const AddObservationLocationScreen({super.key});

  @override
  ConsumerState<AddObservationLocationScreen> createState() =>
      _AddObservationLocationScreenState();
}

class _AddObservationLocationScreenState
    extends ConsumerState<AddObservationLocationScreen> {
  final MapController _mapController = MapController();
  LatLng? _selectedPoint;
  bool _resolvingCurrentLocation = false;

  @override
  void initState() {
    super.initState();
    final location = ref.read(addObservationControllerProvider).location;
    if (location != null) {
      _selectedPoint = LatLng(location.latitude, location.longitude);
    }
  }

  Future<void> _useCurrentLocation() async {
    if (_resolvingCurrentLocation) {
      return;
    }
    if (!await _confirmCurrentLocationUse() || !mounted) {
      return;
    }
    setState(() {
      _resolvingCurrentLocation = true;
    });
    try {
      final location =
          await ref.read(locationServiceProvider).resolveCurrentLocation();
      if (location == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                ref.read(appStringsProvider).couldNotResolveYourLocation,
              ),
            ),
          );
        }
        return;
      }
      ref.read(addObservationControllerProvider.notifier).setLocation(location);
      if (mounted) {
        _returnToForm();
      }
    } finally {
      if (mounted) {
        setState(() {
          _resolvingCurrentLocation = false;
        });
      }
    }
  }

  void _useSelectedLocation() {
    final selectedPoint = _selectedPoint;
    if (selectedPoint == null) {
      return;
    }
    ref.read(addObservationControllerProvider.notifier).setLocation(
          GeoPoint(
            latitude: selectedPoint.latitude,
            longitude: selectedPoint.longitude,
          ),
        );
    _returnToForm();
  }

  void _returnToForm() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/add/details');
    }
  }

  Future<bool> _confirmCurrentLocationUse() async {
    final strings = ref.read(appStringsProvider);
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.useCurrentLocationTitle),
        content: Text(strings.useCurrentLocationMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(strings.continueAction),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(strings.chooseOnMap)),
      body: AppContentWidth(
        maxWidth: AppWidths.readable,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            Text(strings.chooseOnMap,
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.sm),
            Text(
              strings.tapMapForLocation,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              onPressed: _resolvingCurrentLocation ? null : _useCurrentLocation,
              icon: _resolvingCurrentLocation
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location),
              label: Text(strings.useMyCurrentLocation),
            ),
            const SizedBox(height: AppSpacing.md),
            _LocationPickerMap(
              mapController: _mapController,
              selectedPoint: _selectedPoint,
              onTap: (point) {
                setState(() {
                  _selectedPoint = point;
                });
              },
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              onPressed: _selectedPoint == null ? null : _useSelectedLocation,
              icon: const Icon(Icons.check),
              label: Text(strings.useThisLocation),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocationPickerMap extends StatelessWidget {
  const _LocationPickerMap({
    required this.mapController,
    required this.selectedPoint,
    required this.onTap,
  });

  final MapController mapController;
  final LatLng? selectedPoint;
  final ValueChanged<LatLng> onTap;

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>[
      if (selectedPoint != null)
        Marker(
          point: selectedPoint!,
          width: 52,
          height: 52,
          child: Icon(
            Icons.location_on,
            color: Theme.of(context).colorScheme.error,
            size: 48,
          ),
        ),
    ];

    return SizedBox(
      height: 360,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: Stack(
          children: [
            FlutterMap(
              mapController: mapController,
              options: MapOptions(
                initialCenter: selectedPoint ?? const LatLng(41.3111, 69.2797),
                initialZoom: selectedPoint == null ? 13.5 : 15.5,
                cameraConstraint: CameraConstraint.contain(
                  bounds: LatLngBounds(
                    const LatLng(41.1800, 69.0500),
                    const LatLng(41.4300, 69.4200),
                  ),
                ),
                minZoom: 11,
                maxZoom: 18,
                onTap: (_, point) => onTap(point),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'mushukistan_frontend',
                ),
                MarkerLayer(markers: markers),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
