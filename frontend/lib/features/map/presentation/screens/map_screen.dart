import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/location/location_service.dart';
import '../../../../core/network/mushukistan_api.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/widgets/app_surface.dart';

final _tashkentBounds = LatLngBounds(
  const LatLng(41.1800, 69.0500),
  const LatLng(41.4300, 69.4200),
);

const _tashkentBbox = '69.0500,41.1800,69.4200,41.4300';

final mapCatsProvider =
    FutureProvider.autoDispose<ApiPage<CatSummary>>((ref) async {
  final api = ref.watch(mushukistanApiProvider);
  final location = await ref.watch(currentLocationProvider.future);
  if (!_isInsideTashkent(location)) {
    return api.listCats(
      filter: 'recently_added',
      bbox: _tashkentBbox,
      limit: 100,
    );
  }
  return api.listCats(
    filter: 'nearby',
    lat: location.latitude,
    lon: location.longitude,
    radiusMeters: 4000,
    limit: 100,
  );
});

enum _MapLayer {
  cats(Icons.pets, null),
  lostPets(Icons.search_outlined, null),
  vets(Icons.local_hospital_outlined, 'veterinary'),
  shops(Icons.storefront_outlined, 'pet_shop'),
  shelters(Icons.home_work_outlined, 'shelter');

  const _MapLayer(this.icon, this.placeCategory);

  final IconData icon;
  final String? placeCategory;
}

final _mapLayersProvider = StateProvider<Set<_MapLayer>>(
  (ref) => {
    _MapLayer.cats,
    _MapLayer.lostPets,
    _MapLayer.vets,
    _MapLayer.shops,
    _MapLayer.shelters,
  },
);

final mapPlacesProvider =
    FutureProvider.autoDispose<ApiPage<PlaceSummary>>((ref) async {
  final selectedLayers = ref.watch(_mapLayersProvider);
  final categories = selectedLayers
      .map((layer) => layer.placeCategory)
      .whereType<String>()
      .toList(growable: false);
  if (categories.isEmpty) {
    return const ApiPage<PlaceSummary>(items: [], limit: 0);
  }

  final api = ref.watch(mushukistanApiProvider);
  final location = await ref.watch(currentLocationProvider.future);
  if (!_isInsideTashkent(location)) {
    return api.listPlaces(
      categories: categories,
      bbox: _tashkentBbox,
      limit: 200,
    );
  }
  return api.listPlaces(
    categories: categories,
    lat: location.latitude,
    lon: location.longitude,
    radiusMeters: 8000,
    limit: 200,
  );
});

final mapLostPetsProvider =
    FutureProvider.autoDispose<ApiPage<FeedItem>>((ref) async {
  final selectedLayers = ref.watch(_mapLayersProvider);
  if (!selectedLayers.contains(_MapLayer.lostPets)) {
    return const ApiPage<FeedItem>(items: [], limit: 0);
  }

  final api = ref.watch(mushukistanApiProvider);
  final location = await ref.watch(currentLocationProvider.future);
  if (!_isInsideTashkent(location)) {
    return api.listLostPets(
      limit: 100,
      validForMap: true,
    );
  }
  return api.listLostPets(
    lat: location.latitude,
    lon: location.longitude,
    radiusMeters: 5000,
    limit: 100,
    validForMap: true,
  );
});

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key, this.focusLocation});

  final GeoPoint? focusLocation;

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen>
    with SingleTickerProviderStateMixin {
  final MapController _mapController = MapController();
  Timer? _footerTimer;
  bool _showMapFooter = true;
  bool _locationDisclosureAccepted = false;
  bool _refreshingMap = false;
  late final AnimationController _centerAnimationController =
      AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );

  void _centerOnUser(GeoPoint location) {
    final targetCenter = _clampToTashkent(
      LatLng(location.latitude, location.longitude),
    );
    final startCenter = _mapController.camera.center;
    final startZoom = _mapController.camera.zoom;
    const targetZoom = 15.5;

    _centerAnimationController.stop();
    _centerAnimationController.reset();
    void listener() {
      final progress =
          Curves.easeOutCubic.transform(_centerAnimationController.value);
      final latitude = startCenter.latitude +
          (targetCenter.latitude - startCenter.latitude) * progress;
      final longitude = startCenter.longitude +
          (targetCenter.longitude - startCenter.longitude) * progress;
      final zoom = startZoom + (targetZoom - startZoom) * progress;
      _mapController.move(LatLng(latitude, longitude), zoom);
    }

    _centerAnimationController.addListener(listener);
    _centerAnimationController.forward().whenCompleteOrCancel(() {
      _centerAnimationController.removeListener(listener);
    });
  }

  void _showFooterTemporarily() {
    _footerTimer?.cancel();
    if (mounted) {
      setState(() {
        _showMapFooter = true;
      });
    }
    _footerTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _showMapFooter = false;
      });
    });
  }

  Future<void> _openLayerFilterSheet(AppStrings strings) async {
    final currentLayers = ref.read(_mapLayersProvider);
    final selectedLayers = await showModalBottomSheet<Set<_MapLayer>>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        var draftLayers = {...currentLayers};
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.82,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        strings.filters,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      for (final layer in _MapLayer.values)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          secondary: Icon(layer.icon),
                          title: Text(_layerLabel(layer, strings)),
                          value: draftLayers.contains(layer),
                          onChanged: (isSelected) {
                            setSheetState(() {
                              if (isSelected ?? false) {
                                draftLayers.add(layer);
                              } else {
                                draftLayers.remove(layer);
                              }
                            });
                          },
                        ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(sheetContext).pop(),
                              child: Text(strings.cancel),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: () => Navigator.of(sheetContext).pop(
                                draftLayers,
                              ),
                              child: Text(strings.applyFilters),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (!mounted || selectedLayers == null) {
      return;
    }
    _showFooterTemporarily();
    ref.read(_mapLayersProvider.notifier).state = selectedLayers;
  }

  Future<void> _refreshMap() async {
    if (_refreshingMap) {
      return;
    }
    setState(() {
      _refreshingMap = true;
    });
    _showFooterTemporarily();
    try {
      final refreshedLocation = ref.refresh(currentLocationProvider.future);
      await refreshedLocation;
      final refreshedCats = ref.refresh(mapCatsProvider.future);
      final refreshedPlaces = ref.refresh(mapPlacesProvider.future);
      final refreshedLostPets = ref.refresh(mapLostPetsProvider.future);
      await Future.wait([
        refreshedCats,
        refreshedPlaces,
        refreshedLostPets,
      ]);
    } finally {
      if (mounted) {
        setState(() {
          _refreshingMap = false;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _locationDisclosureAccepted = widget.focusLocation != null;
    _showFooterTemporarily();
  }

  @override
  void dispose() {
    _footerTimer?.cancel();
    _centerAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedLayers = ref.watch(_mapLayersProvider);
    final strings = ref.watch(appStringsProvider);
    if (!_locationDisclosureAccepted) {
      return Scaffold(
        body: SafeArea(
          child: AppStatePanel(
            icon: Icons.my_location_outlined,
            title: 'Use your location',
            message:
                'Mushukistan uses your current location to show nearby cats and useful places. It is not published unless you create a public post.',
            action: FilledButton.icon(
              onPressed: () {
                setState(() {
                  _locationDisclosureAccepted = true;
                });
              },
              icon: const Icon(Icons.location_searching),
              label: const Text('Use my location'),
            ),
          ),
        ),
      );
    }
    final locationAsync = ref.watch(currentLocationProvider);
    final showCats = selectedLayers.contains(_MapLayer.cats);
    final catsAsync = showCats
        ? ref.watch(mapCatsProvider)
        : const AsyncData<ApiPage<CatSummary>>(
            ApiPage<CatSummary>(items: [], limit: 0),
          );
    final placesAsync = ref.watch(mapPlacesProvider);
    final lostPetsAsync = ref.watch(mapLostPetsProvider);

    return Scaffold(
      body: locationAsync.when(
        data: (location) {
          final focusLocation = widget.focusLocation;
          final center = _clampToTashkent(
            focusLocation == null
                ? LatLng(location.latitude, location.longitude)
                : LatLng(focusLocation.latitude, focusLocation.longitude),
          );
          final currentLocationPoint = _clampToTashkent(
            LatLng(location.latitude, location.longitude),
          );
          return catsAsync.when(
            data: (catPage) {
              return placesAsync.when(
                data: (placePage) {
                  final lostPets = lostPetsAsync.valueOrNull?.items
                          .whereType<LostPetData>()
                          .toList(growable: false) ??
                      const <LostPetData>[];
                  final markers = <Marker>[
                    Marker(
                      point: currentLocationPoint,
                      width: 40,
                      height: 40,
                      child: const _CurrentLocationMarker(),
                    ),
                    if (focusLocation != null)
                      Marker(
                        point: center,
                        width: 52,
                        height: 52,
                        child: const _FocusedLostPetMarker(),
                      ),
                    if (showCats)
                      ...catPage.items
                          .where((cat) => cat.canonicalLocation != null)
                          .map(
                            (cat) => Marker(
                              point: LatLng(
                                cat.canonicalLocation!.latitude,
                                cat.canonicalLocation!.longitude,
                              ),
                              width: 44,
                              height: 44,
                              child: _CatMarker(
                                status: cat.status,
                                onTap: () {},
                              ),
                            ),
                          ),
                    ...lostPets.map(
                      (lostPet) => Marker(
                        point: LatLng(
                          lostPet.lastSeenLocation.latitude,
                          lostPet.lastSeenLocation.longitude,
                        ),
                        width: 48,
                        height: 48,
                        child: _MapLostPetMarker(
                          onTap: () =>
                              _showLostPetSheet(context, lostPet, strings),
                        ),
                      ),
                    ),
                    ...placePage.items.map(
                      (place) => Marker(
                        point: LatLng(
                          place.location.latitude,
                          place.location.longitude,
                        ),
                        width: 32,
                        height: 32,
                        child: _PlaceMarker(
                          category: place.category,
                          onTap: () => _showPlaceSheet(
                            context,
                            place,
                            strings,
                          ),
                        ),
                      ),
                    ),
                  ];

                  return Stack(
                    children: [
                      FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: center,
                          initialZoom: focusLocation == null ? 13.6 : 16,
                          cameraConstraint: CameraConstraint.contain(
                            bounds: _tashkentBounds,
                          ),
                          minZoom: 12.5,
                          maxZoom: 18,
                          interactionOptions: const InteractionOptions(
                            flags: InteractiveFlag.all,
                          ),
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'mushukistan_frontend',
                          ),
                          MarkerLayer(markers: markers),
                          RichAttributionWidget(
                            attributions: [
                              TextSourceAttribution(
                                'OpenStreetMap contributors',
                                onTap: () => _openOsmCopyright(),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Positioned(
                        left: 12,
                        top: 12,
                        child: SafeArea(
                          child: _MapControlButton(
                            heroTag: 'map-refresh',
                            tooltip: strings.refresh,
                            icon: _refreshingMap
                                ? Icons.hourglass_top
                                : Icons.refresh,
                            onPressed: _refreshMap,
                          ),
                        ),
                      ),
                      Positioned(
                        right: 12,
                        top: 12,
                        child: SafeArea(
                          child: _LayerFilterButton(
                            selectedLayers: selectedLayers,
                            strings: strings,
                            onPressed: () => _openLayerFilterSheet(strings),
                          ),
                        ),
                      ),
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOutCubic,
                        right: 16,
                        bottom: _showMapFooter ? 104 : 24,
                        child: FloatingActionButton.small(
                          heroTag: 'map-center-on-user',
                          tooltip: strings.centerOnUser,
                          onPressed: () => _centerOnUser(location),
                          child: const Icon(Icons.my_location),
                        ),
                      ),
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 16,
                        child: IgnorePointer(
                          ignoring: !_showMapFooter,
                          child: AnimatedOpacity(
                            opacity: _showMapFooter ? 1 : 0,
                            duration: const Duration(milliseconds: 250),
                            child: _MapFooter(
                              catCount: showCats ? catPage.items.length : 0,
                              lostPetCount: lostPets.length,
                              placeCount: placePage.items.length,
                              location: location,
                              strings: strings,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stackTrace) => _ErrorPanel(
                  title: strings.couldNotLoadPlaceMarkers,
                  message: error.toString(),
                  retryLabel: strings.retry,
                  onRetry: () => ref.invalidate(mapPlacesProvider),
                ),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stackTrace) => _ErrorPanel(
              title: strings.couldNotLoadCatMarkers,
              message: error.toString(),
              retryLabel: strings.retry,
              onRetry: () => ref.invalidate(mapCatsProvider),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => _ErrorPanel(
          title: strings.couldNotResolveLocation,
          message: error.toString(),
          retryLabel: strings.retry,
          onRetry: () {
            _showFooterTemporarily();
            ref.invalidate(currentLocationProvider);
            ref.invalidate(mapCatsProvider);
            ref.invalidate(mapPlacesProvider);
            ref.invalidate(mapLostPetsProvider);
          },
        ),
      ),
    );
  }
}

Future<void> _openOsmCopyright() async {
  await launchUrl(
    Uri.parse('https://www.openstreetmap.org/copyright'),
    mode: LaunchMode.externalApplication,
  );
}

String _formatDate(DateTime dateTime) {
  final local = dateTime.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}

void _showPlaceSheet(
  BuildContext context,
  PlaceSummary place,
  AppStrings strings,
) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _PlaceBadge(category: place.category),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      place.name,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
              if (place.address != null) ...[
                const SizedBox(height: 12),
                _PlaceDetailRow(
                  icon: Icons.place_outlined,
                  text: place.address!,
                ),
              ],
              if (place.phone != null) ...[
                const SizedBox(height: 8),
                _PlaceDetailRow(
                  icon: Icons.phone_outlined,
                  text: place.phone!,
                ),
              ],
              if (place.openingHours != null) ...[
                const SizedBox(height: 8),
                _PlaceDetailRow(
                  icon: Icons.schedule_outlined,
                  text: place.openingHours!,
                ),
              ],
              if (place.website != null) ...[
                const SizedBox(height: 8),
                _PlaceDetailRow(
                  icon: Icons.language_outlined,
                  text: place.website!,
                ),
              ],
              const SizedBox(height: 12),
              Text(
                place.source == 'osm'
                    ? strings.sourceOpenStreetMap
                    : strings.sourceMushukistan,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
    },
  );
}

void _showLostPetSheet(
  BuildContext context,
  LostPetData lostPet,
  AppStrings strings,
) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: theme.colorScheme.errorContainer,
                    child: Icon(
                      Icons.search,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      lostPet.petName,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text('${strings.lostPet} · ${_formatDate(lostPet.createdAt)}'),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  context.push('/lost-pets/${lostPet.id}');
                },
                icon: const Icon(Icons.open_in_new),
                label: Text(strings.openPost),
              ),
            ],
          ),
        ),
      );
    },
  );
}

LatLng _clampToTashkent(LatLng point) {
  final latitude = point.latitude.clamp(
    _tashkentBounds.south,
    _tashkentBounds.north,
  );
  final longitude = point.longitude.clamp(
    _tashkentBounds.west,
    _tashkentBounds.east,
  );
  return LatLng(latitude, longitude);
}

bool _isInsideTashkent(GeoPoint point) {
  return point.latitude >= _tashkentBounds.south &&
      point.latitude <= _tashkentBounds.north &&
      point.longitude >= _tashkentBounds.west &&
      point.longitude <= _tashkentBounds.east;
}

class _CurrentLocationMarker extends StatelessWidget {
  const _CurrentLocationMarker();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            shape: BoxShape.circle,
          ),
          child: const SizedBox(width: 14, height: 14),
        ),
      ),
    );
  }
}

class _FocusedLostPetMarker extends StatelessWidget {
  const _FocusedLostPetMarker();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.error.withValues(alpha: 0.18),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.error,
            shape: BoxShape.circle,
            boxShadow: const [
              BoxShadow(
                blurRadius: 8,
                color: Color(0x44000000),
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: _MarkerIcon(
            icon: Icons.priority_high,
            color: colorScheme.onError,
            size: 28,
          ),
        ),
      ),
    );
  }
}

class _CatMarker extends StatelessWidget {
  const _CatMarker({
    required this.status,
    required this.onTap,
  });

  final String status;
  final VoidCallback onTap;

  Color _color(BuildContext context) {
    switch (status) {
      case 'healthy':
        return AppPalette.found;
      case 'injured':
        return AppPalette.terracotta;
      case 'needs_help':
        return Theme.of(context).colorScheme.error;
      case 'adopted':
        return AppPalette.adoption;
      case 'feed':
        return AppPalette.sage;
      default:
        return Theme.of(context).colorScheme.secondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _color(context);
    return GestureDetector(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          shape: BoxShape.circle,
          border: Border.all(color: color.withValues(alpha: 0.35)),
          boxShadow: const [
            BoxShadow(
              blurRadius: 6,
              color: Color(0x33000000),
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: _MarkerIcon(
            icon: Icons.pets,
            color: color,
            size: 22,
          ),
        ),
      ),
    );
  }
}

class _PlaceMarker extends StatelessWidget {
  const _PlaceMarker({
    required this.category,
    required this.onTap,
  });

  final String category;
  final VoidCallback onTap;

  Color _color(BuildContext context) {
    switch (category) {
      case 'veterinary':
        return AppPalette.lost;
      case 'shelter':
        return AppPalette.sageDark;
      default:
        return AppPalette.adoption;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _color(context);
    return GestureDetector(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          shape: BoxShape.circle,
          boxShadow: const [
            BoxShadow(
              blurRadius: 5,
              color: Color(0x33000000),
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: Center(
          child: _MarkerIcon(
            icon: _icon,
            color: color,
            size: 18,
          ),
        ),
      ),
    );
  }

  IconData get _icon => switch (category) {
        'veterinary' => Icons.local_hospital,
        'shelter' => Icons.home_work,
        _ => Icons.storefront,
      };
}

class _MapLostPetMarker extends StatelessWidget {
  const _MapLostPetMarker({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.error.withValues(alpha: 0.18),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colorScheme.error,
              shape: BoxShape.circle,
              boxShadow: const [
                BoxShadow(
                  blurRadius: 6,
                  color: Color(0x33000000),
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: _MarkerIcon(
              icon: Icons.priority_high,
              color: colorScheme.onError,
              size: 26,
            ),
          ),
        ),
      ),
    );
  }
}

class _MarkerIcon extends StatelessWidget {
  const _MarkerIcon({
    required this.icon,
    required this.color,
    required this.size,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(icon, color: color, size: size),
    );
  }
}

class _LayerFilterButton extends StatelessWidget {
  const _LayerFilterButton({
    required this.selectedLayers,
    required this.strings,
    required this.onPressed,
  });

  final Set<_MapLayer> selectedLayers;
  final AppStrings strings;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Badge.count(
      count: selectedLayers.length,
      isLabelVisible: selectedLayers.isNotEmpty,
      child: _MapControlButton(
        heroTag: 'map-filter-layers',
        tooltip: strings.filters,
        icon: Icons.tune,
        onPressed: onPressed,
      ),
    );
  }
}

class _MapControlButton extends StatelessWidget {
  const _MapControlButton({
    required this.heroTag,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String heroTag;
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return FloatingActionButton.small(
      heroTag: heroTag,
      tooltip: tooltip,
      elevation: 3,
      backgroundColor: colors.surface,
      foregroundColor: colors.onSurface,
      onPressed: onPressed,
      child: Icon(icon),
    );
  }
}

String _layerLabel(_MapLayer layer, AppStrings strings) {
  return switch (layer) {
    _MapLayer.cats => strings.cats,
    _MapLayer.lostPets => strings.lostPets,
    _MapLayer.vets => strings.vets,
    _MapLayer.shops => strings.shops,
    _MapLayer.shelters => strings.shelters,
  };
}

class _PlaceBadge extends StatelessWidget {
  const _PlaceBadge({required this.category});

  final String category;

  @override
  Widget build(BuildContext context) {
    final icon = switch (category) {
      'veterinary' => Icons.local_hospital,
      'shelter' => Icons.home_work,
      _ => Icons.storefront,
    };
    return CircleAvatar(
      child: Icon(icon),
    );
  }
}

class _PlaceDetailRow extends StatelessWidget {
  const _PlaceDetailRow({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
      ],
    );
  }
}

class _MapFooter extends StatelessWidget {
  const _MapFooter({
    required this.catCount,
    required this.lostPetCount,
    required this.placeCount,
    required this.location,
    required this.strings,
  });

  final int catCount;
  final int lostPetCount;
  final int placeCount;
  final GeoPoint location;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.location_on_outlined),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '${strings.showingMapItems(
                  catCount: catCount,
                  placeCount: placeCount,
                  latitude: location.latitude,
                  longitude: location.longitude,
                )} · ${strings.lostPets}: $lostPetCount',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({
    required this.title,
    required this.message,
    required this.retryLabel,
    required this.onRetry,
  });

  final String title;
  final String message;
  final String retryLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return AppStatePanel(
      icon: Icons.map_outlined,
      title: title,
      message: message,
      action: FilledButton(onPressed: onRetry, child: Text(retryLabel)),
    );
  }
}
