import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/location/location_service.dart';
import '../../../../core/network/mushukistan_api.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../application/add_observation_controller.dart';

final _locationPickerCurrentLocationProvider =
    FutureProvider.autoDispose<GeoPoint>((ref) async {
  return LocationService().resolveCurrentLocation();
});

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
  bool _showMapPicker = false;
  bool _resolvingCurrentLocation = false;

  Future<void> _useCurrentLocation() async {
    if (_resolvingCurrentLocation) {
      return;
    }
    setState(() {
      _resolvingCurrentLocation = true;
    });
    try {
      final location =
          await ref.read(_locationPickerCurrentLocationProvider.future);
      ref.read(addObservationControllerProvider.notifier).setLocation(location);
      unawaited(
        ref.read(addObservationControllerProvider.notifier).loadNearbyCats(),
      );
      if (mounted) {
        context.go('/add/details');
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
    unawaited(
      ref.read(addObservationControllerProvider.notifier).loadNearbyCats(),
    );
    context.go('/add/details');
  }

  void _skipLocation() {
    ref.read(addObservationControllerProvider.notifier).clearLocation();
    context.go('/add/details');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(addObservationControllerProvider);
    final currentLocationAsync =
        ref.watch(_locationPickerCurrentLocationProvider);

    if (!state.hasPhoto) {
      return Scaffold(
        appBar: AppBar(title: const Text('Observation location')),
        body: AppStatePanel(
          icon: Icons.photo_library_outlined,
          title: 'Choose a photo first.',
          action: FilledButton(
            onPressed: () => context.go('/add'),
            child: const Text('Back to Add'),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Observation location')),
      body: AppContentWidth(
        maxWidth: AppWidths.readable,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            Text(
              'Attach a location?',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'A location makes the observation visible on the map. Skip it if the photo is old or the place is uncertain.',
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
              label: const Text('Use my current location'),
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _showMapPicker = true;
                });
              },
              icon: const Icon(Icons.add_location_alt_outlined),
              label: const Text('Mark on map'),
            ),
            const SizedBox(height: AppSpacing.md),
            TextButton.icon(
              onPressed: _skipLocation,
              icon: const Icon(Icons.location_off_outlined),
              label: const Text('Continue without location'),
            ),
            if (_showMapPicker) ...[
              const SizedBox(height: AppSpacing.xl),
              currentLocationAsync.when(
                data: (location) => _LocationPickerMap(
                  mapController: _mapController,
                  currentLocation: location,
                  selectedPoint: _selectedPoint,
                  onTap: (point) {
                    setState(() {
                      _selectedPoint = point;
                    });
                  },
                  onCenterOnUser: () {
                    final point = LatLng(location.latitude, location.longitude);
                    _mapController.move(point, 16);
                    setState(() {
                      _selectedPoint ??= point;
                    });
                  },
                ),
                loading: () => const SizedBox(
                  height: 320,
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, stackTrace) => AppStatePanel(
                  icon: Icons.location_off_outlined,
                  title: 'Could not resolve your location.',
                  message: error.toString(),
                  action: FilledButton(
                    onPressed: () => ref.invalidate(
                      _locationPickerCurrentLocationProvider,
                    ),
                    child: const Text('Retry'),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              FilledButton.icon(
                onPressed: _selectedPoint == null ? null : _useSelectedLocation,
                icon: const Icon(Icons.check),
                label: const Text('Use this location'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LocationPickerMap extends StatelessWidget {
  const _LocationPickerMap({
    required this.mapController,
    required this.currentLocation,
    required this.selectedPoint,
    required this.onTap,
    required this.onCenterOnUser,
  });

  final MapController mapController;
  final GeoPoint currentLocation;
  final LatLng? selectedPoint;
  final ValueChanged<LatLng> onTap;
  final VoidCallback onCenterOnUser;

  @override
  Widget build(BuildContext context) {
    final userPoint = LatLng(
      currentLocation.latitude,
      currentLocation.longitude,
    );
    final markers = <Marker>[
      Marker(
        point: userPoint,
        width: 54,
        height: 54,
        child: const _VisibleCurrentLocationMarker(),
      ),
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
                initialCenter: selectedPoint ?? userPoint,
                initialZoom: 15.5,
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
            Positioned(
              right: 12,
              top: 12,
              child: FloatingActionButton.small(
                heroTag: 'add-location-center-on-user',
                tooltip: 'Center on user',
                onPressed: onCenterOnUser,
                child: const Icon(Icons.my_location),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VisibleCurrentLocationMarker extends StatelessWidget {
  const _VisibleCurrentLocationMarker();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.22),
        shape: BoxShape.circle,
        border: Border.all(
          color: colors.surface,
          width: 3,
        ),
        boxShadow: const [
          BoxShadow(
            blurRadius: 10,
            color: Color(0x55000000),
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.primary,
            shape: BoxShape.circle,
            border: Border.all(color: colors.surface, width: 3),
          ),
          child: const SizedBox(width: 18, height: 18),
        ),
      ),
    );
  }
}
