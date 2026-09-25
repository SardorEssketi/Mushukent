import 'dart:async';
import 'dart:math' as math;

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
import '../../../../core/validation/phone_numbers.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../../../core/widgets/marker_detail_actions.dart';
import '../../application/map_viewport.dart';

final _tashkentBounds = LatLngBounds(
  const LatLng(41.1800, 69.0500),
  const LatLng(41.4300, 69.4200),
);

/// This stays null until the user explicitly asks to use device location.
/// Tashkent remains a map viewport and query fallback, never a user location.
final _mapSearchLocationProvider = StateProvider<GeoPoint?>((ref) => null);

enum _MapLayer {
  observations(Icons.pets, null),
  needsHelp(Icons.warning_amber_outlined, null),
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
    _MapLayer.observations,
    _MapLayer.needsHelp,
    _MapLayer.lostPets,
    _MapLayer.vets,
    _MapLayer.shops,
    _MapLayer.shelters,
  },
);

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key, this.focusLocation});

  final GeoPoint? focusLocation;

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen>
    with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  AnimationController? _centerAnimationController;
  late final ViewportRequestScheduler _viewportScheduler;
  MapCamera? _currentCamera;
  ApiPage<CatSummary>? _catPage;
  ApiPage<PlaceSummary>? _placePage;
  ApiPage<LostPetMapData>? _lostPetPage;
  Object? _mapError;
  final ViewportRequestGuard _viewportRequestGuard = ViewportRequestGuard();
  bool _mapReady = false;
  bool _refreshingMap = false;

  @override
  void initState() {
    super.initState();
    _viewportScheduler = ViewportRequestScheduler(
      onScheduled: _viewportRequestGuard.invalidate,
      onSettled: (query) => unawaited(_loadViewport(query)),
    );
  }

  String _filterKey(Set<_MapLayer> layers) {
    return (_MapLayer.values
            .where(layers.contains)
            .map((layer) => layer.name)
            .toList(growable: false))
        .join(',');
  }

  String? _catKind(Set<_MapLayer> layers) {
    final showObservations = layers.contains(_MapLayer.observations);
    final showNeedsHelp = layers.contains(_MapLayer.needsHelp);
    if (showObservations == showNeedsHelp) {
      return null;
    }
    return showNeedsHelp ? 'needs_help' : 'observation';
  }

  void _onMapReady() {
    if (_mapReady || !mounted) {
      return;
    }
    _mapReady = true;
    _onCameraChanged(_mapController.camera, true, force: true);
  }

  void _onCameraChanged(
    MapCamera camera,
    bool hasGesture, {
    bool force = false,
  }) {
    if (!_mapReady && !force) {
      return;
    }
    _currentCamera = camera;
    final query = MapViewportQuery.fromCamera(
      camera,
      allowedBounds: _tashkentBounds,
    );
    _viewportScheduler.schedule(
      query,
      filterKey: _filterKey(ref.read(_mapLayersProvider)),
      force: force,
    );
  }

  Future<void> _loadViewport(MapViewportQuery query) async {
    if (!mounted) {
      return;
    }
    final requestGeneration = _viewportRequestGuard.begin();
    final layers = ref.read(_mapLayersProvider);
    final showCats = layers.contains(_MapLayer.observations) ||
        layers.contains(_MapLayer.needsHelp);
    final categories = layers
        .map((layer) => layer.placeCategory)
        .whereType<String>()
        .toList(growable: false);
    final catKind = _catKind(layers);
    final api = ref.read(mushukistanApiProvider);

    if (mounted) {
      setState(() {
        _refreshingMap = true;
        _mapError = null;
      });
    }

    try {
      final catsFuture = showCats
          ? api.listCats(
              filter: 'recently_added',
              bbox: query.bbox,
              limit: 100,
              kind: catKind,
            )
          : Future<ApiPage<CatSummary>?>.value(null);
      final placesFuture = categories.isEmpty
          ? Future<ApiPage<PlaceSummary>?>.value(null)
          : api
              .listPlaces(
                categories: categories,
                bbox: query.bbox,
                limit: 200,
                mapOnly: true,
              )
              .then<ApiPage<PlaceSummary>?>((page) => page);
      final lostPetsFuture = layers.contains(_MapLayer.lostPets)
          ? api
              .listMapLostPets(bbox: query.bbox, limit: 100)
              .then<ApiPage<LostPetMapData>?>((page) => page)
          : Future<ApiPage<LostPetMapData>?>.value(null);
      final results = await Future.wait<Object?>([
        catsFuture,
        placesFuture,
        lostPetsFuture,
      ]);
      if (!mounted || !_viewportRequestGuard.isCurrent(requestGeneration)) {
        return;
      }
      setState(() {
        _catPage = results[0] as ApiPage<CatSummary>? ?? _catPage;
        _placePage = results[1] as ApiPage<PlaceSummary>? ?? _placePage;
        _lostPetPage = results[2] as ApiPage<LostPetMapData>? ?? _lostPetPage;
      });
    } catch (error) {
      if (mounted && _viewportRequestGuard.isCurrent(requestGeneration)) {
        setState(() {
          _mapError = error;
        });
      }
    } finally {
      if (mounted && _viewportRequestGuard.isCurrent(requestGeneration)) {
        setState(() {
          _refreshingMap = false;
        });
      }
    }
  }

  void _centerOnLocation(LatLng targetCenter, double targetZoom) {
    final camera = _mapController.camera;
    final latTween = Tween<double>(
      begin: camera.center.latitude,
      end: targetCenter.latitude,
    );
    final lonTween = Tween<double>(
      begin: camera.center.longitude,
      end: targetCenter.longitude,
    );
    final zoomTween = Tween<double>(
      begin: camera.zoom,
      end: targetZoom,
    );
    final rotationStart = camera.rotation;
    final rotationDelta = _shortestRotationDelta(rotationStart, 0);

    _centerAnimationController?.dispose();
    final controller = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _centerAnimationController = controller;
    final animation = CurvedAnimation(
      parent: controller,
      curve: Curves.easeOutCubic,
    );

    controller.addListener(() {
      final progress = animation.value;
      _mapController.moveAndRotate(
        LatLng(
          latTween.evaluate(animation),
          lonTween.evaluate(animation),
        ),
        zoomTween.evaluate(animation),
        rotationStart + rotationDelta * progress,
      );
    });
    controller.addStatusListener((status) {
      if (status != AnimationStatus.completed &&
          status != AnimationStatus.dismissed) {
        return;
      }
      if (status == AnimationStatus.completed && mounted) {
        // Normalize shortest-path rotations such as 350° -> 360° to 0°.
        _mapController.moveAndRotate(targetCenter, targetZoom, 0);
      }
      if (identical(_centerAnimationController, controller)) {
        _centerAnimationController = null;
      }
      controller.dispose();
    });
    controller.forward();
  }

  void _centerOnUser(GeoPoint location) {
    final targetCenter = _clampToTashkent(
      LatLng(location.latitude, location.longitude),
    );
    _centerOnLocation(targetCenter, 15.5);
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
    ref.read(_mapLayersProvider.notifier).state = selectedLayers;
    if (_currentCamera != null) {
      _onCameraChanged(_currentCamera!, true);
    }
  }

  Future<void> _refreshMap() async {
    if (_refreshingMap) {
      return;
    }
    final camera = _currentCamera;
    if (camera != null) {
      _onCameraChanged(camera, false, force: true);
    }
  }

  Future<void> _requestAndCenterOnUser() async {
    final location = await LocationService().resolveCurrentLocation();
    if (!mounted) {
      return;
    }
    if (location == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ref.read(appStringsProvider).couldNotResolveLocation),
        ),
      );
      return;
    }
    ref.read(_mapSearchLocationProvider.notifier).state = location;
    if (_isInsideTashkent(location)) {
      _centerOnUser(location);
    } else {
      _centerOnLocation(
        LatLng(
          LocationService.fallbackLocation.latitude,
          LocationService.fallbackLocation.longitude,
        ),
        13.6,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(ref.read(appStringsProvider).locationOutsideMap)),
      );
    }
  }

  Future<void> _openLatestCatPost(CatSummary cat) async {
    try {
      final page = await ref.read(mushukistanApiProvider).listCatPosts(
            cat.id,
            limit: 1,
            sort: 'latest',
            includeViewerContext: false,
          );
      if (!mounted) {
        return;
      }
      if (page.items.isEmpty) {
        final strings = ref.read(appStringsProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.noPublicPostFoundForCat)),
        );
        return;
      }
      context.push('/posts/${page.items.first.id}');
    } catch (error) {
      if (!mounted) {
        return;
      }
      final strings = ref.read(appStringsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.couldNotOpenPost(error))),
      );
    }
  }

  void _zoomIntoCluster(LatLng point) {
    final camera = _currentCamera;
    if (!_mapReady || camera == null) {
      return;
    }
    _centerOnLocation(point, math.min(camera.zoom + 2, 16));
  }

  @override
  Widget build(BuildContext context) {
    final selectedLayers = ref.watch(_mapLayersProvider);
    final strings = ref.watch(appStringsProvider);
    ref.listen<int>(postMutationRevisionProvider, (previous, next) {
      if (previous != next && _mapReady) {
        _onCameraChanged(_mapController.camera, false, force: true);
      }
    });
    final selectedLocation = ref.watch(_mapSearchLocationProvider);
    final showObservations = selectedLayers.contains(_MapLayer.observations);
    final showNeedsHelp = selectedLayers.contains(_MapLayer.needsHelp);
    final focusLocation = widget.focusLocation;
    final mapLocation =
        selectedLocation != null && _isInsideTashkent(selectedLocation)
            ? selectedLocation
            : null;
    final center = _clampToTashkent(
      focusLocation != null
          ? LatLng(focusLocation.latitude, focusLocation.longitude)
          : mapLocation != null
              ? LatLng(mapLocation.latitude, mapLocation.longitude)
              : LatLng(
                  LocationService.fallbackLocation.latitude,
                  LocationService.fallbackLocation.longitude,
                ),
    );
    final fixedMarkers = <Marker>[
      if (mapLocation != null)
        Marker(
          point: _clampToTashkent(
            LatLng(mapLocation.latitude, mapLocation.longitude),
          ),
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
    ];
    final normalCatSpecs = <_MapMarkerSpec>[];
    final needsHelpSpecs = <_MapMarkerSpec>[];
    for (final cat in _catPage?.items ?? const <CatSummary>[]) {
      final location = cat.canonicalLocation;
      if (location == null) {
        continue;
      }
      final needsHelp = mapMarkerKindForPostKind(cat.latestPostKind) ==
          MapMarkerKind.needsHelp;
      if (needsHelp && !showNeedsHelp || !needsHelp && !showObservations) {
        continue;
      }
      final spec = _MapMarkerSpec(
        id: cat.id,
        point: LatLng(location.latitude, location.longitude),
        width: 44,
        height: 44,
        child: _CatMarker(
          needsHelp: needsHelp,
          onTap: () => _showCatSheet(
            context,
            cat,
            strings,
            onOpenPost: () => unawaited(_openLatestCatPost(cat)),
          ),
        ),
      );
      (needsHelp ? needsHelpSpecs : normalCatSpecs).add(spec);
    }

    final lostPetSpecs = <_MapMarkerSpec>[];
    if (selectedLayers.contains(_MapLayer.lostPets)) {
      for (final lostPet in _lostPetPage?.items ?? const <LostPetMapData>[]) {
        lostPetSpecs.add(
          _MapMarkerSpec(
            id: lostPet.id,
            point: LatLng(
              lostPet.lastSeenLocation.latitude,
              lostPet.lastSeenLocation.longitude,
            ),
            width: 48,
            height: 48,
            child: _MapLostPetMarker(
              onTap: () => _showLostPetSheet(context, lostPet, strings),
            ),
          ),
        );
      }
    }

    final placeSpecsByCategory = <String, List<_MapMarkerSpec>>{};
    for (final place in _placePage?.items ?? const <PlaceSummary>[]) {
      if (!_isPlaceCategoryVisible(selectedLayers, place.category)) {
        continue;
      }
      placeSpecsByCategory.putIfAbsent(place.category, () => []).add(
            _MapMarkerSpec(
              id: place.id,
              point: LatLng(place.location.latitude, place.location.longitude),
              width: 44,
              height: 44,
              child: _PlaceMarker(
                category: place.category,
                onTap: () => _showPlaceSheet(
                  context,
                  place,
                  strings,
                  ref.read(mushukistanApiProvider),
                ),
              ),
            ),
          );
    }

    final clusteredMarkers = <Marker>[
      ..._clusterMarkerSpecs(
        normalCatSpecs,
        camera: _currentCamera,
        clusterKind: _MapClusterKind.observations,
        onClusterTap: _zoomIntoCluster,
      ),
      ..._clusterMarkerSpecs(
        needsHelpSpecs,
        camera: _currentCamera,
        clusterKind: _MapClusterKind.needsHelp,
        onClusterTap: _zoomIntoCluster,
      ),
      ..._clusterMarkerSpecs(
        lostPetSpecs,
        camera: _currentCamera,
        clusterKind: _MapClusterKind.lostPets,
        onClusterTap: _zoomIntoCluster,
      ),
      for (final entry in placeSpecsByCategory.entries)
        ..._clusterMarkerSpecs(
          entry.value,
          camera: _currentCamera,
          clusterKind: _placeClusterKind(entry.key),
          onClusterTap: _zoomIntoCluster,
        ),
    ];
    final markers = [...fixedMarkers, ...clusteredMarkers];

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: center,
              initialZoom: focusLocation == null ? 13.6 : 16,
              cameraConstraint:
                  CameraConstraint.contain(bounds: _tashkentBounds),
              minZoom: 12.5,
              maxZoom: 18,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all,
              ),
              onMapReady: _onMapReady,
              onPositionChanged: _onCameraChanged,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
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
                tooltip: strings.refresh,
                icon: _refreshingMap ? Icons.hourglass_top : Icons.refresh,
                onPressed: _refreshMap,
              ),
            ),
          ),
          Positioned(
            right: 12,
            top: 12,
            child: SafeArea(
              child: _LayerFilterButton(
                strings: strings,
                onPressed: () => _openLayerFilterSheet(strings),
              ),
            ),
          ),
          if (_mapError != null)
            Positioned(
              left: 12,
              right: 76,
              bottom: 24,
              child: SafeArea(
                child: _MapLoadError(
                  message: strings.couldNotLoadSection,
                  retryLabel: strings.retry,
                  onRetry: _refreshMap,
                ),
              ),
            ),
          Positioned(
            right: 12,
            bottom: 24,
            child: FloatingActionButton(
              heroTag: 'map-center-on-user',
              tooltip: strings.centerOnUser,
              onPressed: _requestAndCenterOnUser,
              child: const Icon(Icons.my_location),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _viewportScheduler.dispose();
    _centerAnimationController?.dispose();
    _mapController.dispose();
    super.dispose();
  }
}

bool _isPlaceCategoryVisible(Set<_MapLayer> layers, String category) {
  return switch (category) {
    'veterinary' => layers.contains(_MapLayer.vets),
    'shelter' => layers.contains(_MapLayer.shelters),
    'pet_shop' => layers.contains(_MapLayer.shops),
    _ => false,
  };
}

bool _placeSupportsRoute(String category) {
  return category == 'veterinary' || category == 'pet_shop';
}

enum _MapClusterKind {
  observations,
  needsHelp,
  lostPets,
  veterinary,
  petShop,
  shelter,
}

class _MapMarkerSpec {
  const _MapMarkerSpec({
    required this.id,
    required this.point,
    required this.width,
    required this.height,
    required this.child,
  });

  final String id;
  final LatLng point;
  final double width;
  final double height;
  final Widget child;
}

_MapClusterKind _placeClusterKind(String category) {
  return switch (category) {
    'veterinary' => _MapClusterKind.veterinary,
    'shelter' => _MapClusterKind.shelter,
    _ => _MapClusterKind.petShop,
  };
}

List<Marker> _clusterMarkerSpecs(
  List<_MapMarkerSpec> specs, {
  required MapCamera? camera,
  required _MapClusterKind clusterKind,
  required void Function(LatLng point) onClusterTap,
}) {
  if (specs.isEmpty) {
    return const <Marker>[];
  }
  final cellSize =
      camera == null ? null : mapClusterCellSizeForZoom(camera.zoom);
  if (cellSize == null) {
    return [
      for (final spec in specs)
        Marker(
          key: ValueKey<String>('marker:${clusterKind.name}:${spec.id}'),
          point: spec.point,
          width: spec.width,
          height: spec.height,
          child: spec.child,
        ),
    ];
  }

  final groups = <String, List<_MapMarkerSpec>>{};
  for (final spec in specs) {
    final projected = camera!.projectAtZoom(spec.point, camera.zoom);
    final cellX = (projected.dx / cellSize).floor();
    final cellY = (projected.dy / cellSize).floor();
    groups.putIfAbsent('$cellX:$cellY', () => []).add(spec);
  }

  return [
    for (final entry in groups.entries)
      if (entry.value.length == 1)
        Marker(
          key: ValueKey<String>(
              'marker:${clusterKind.name}:${entry.value.single.id}'),
          point: entry.value.single.point,
          width: entry.value.single.width,
          height: entry.value.single.height,
          child: entry.value.single.child,
        )
      else
        Marker(
          key: ValueKey<String>('cluster:${clusterKind.name}:${entry.key}'),
          point: _clusterCenter(entry.value),
          width: 52,
          height: 52,
          child: _MapClusterMarker(
            count: entry.value.length,
            kind: clusterKind,
            onTap: () => onClusterTap(_clusterCenter(entry.value)),
          ),
        ),
  ];
}

LatLng _clusterCenter(List<_MapMarkerSpec> specs) {
  var latitude = 0.0;
  var longitude = 0.0;
  for (final spec in specs) {
    latitude += spec.point.latitude;
    longitude += spec.point.longitude;
  }
  return LatLng(latitude / specs.length, longitude / specs.length);
}

class _MapClusterMarker extends StatelessWidget {
  const _MapClusterMarker({
    required this.count,
    required this.kind,
    required this.onTap,
  });

  final int count;
  final _MapClusterKind kind;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isPlace = switch (kind) {
      _MapClusterKind.veterinary ||
      _MapClusterKind.petShop ||
      _MapClusterKind.shelter =>
        true,
      _ => false,
    };
    final alert =
        kind == _MapClusterKind.needsHelp || kind == _MapClusterKind.lostPets;
    final color = switch (kind) {
      _MapClusterKind.needsHelp => colors.tertiary,
      _MapClusterKind.lostPets => colors.error,
      _MapClusterKind.veterinary => AppPalette.lost,
      _MapClusterKind.shelter => AppPalette.sageDark,
      _MapClusterKind.petShop => AppPalette.adoption,
      _MapClusterKind.observations => colors.secondary,
    };
    final icon = switch (kind) {
      _MapClusterKind.needsHelp =>
        mapMarkerIconForKind(MapMarkerKind.needsHelp),
      _MapClusterKind.lostPets => mapMarkerIconForKind(MapMarkerKind.lostPet),
      _MapClusterKind.veterinary => Icons.local_hospital,
      _MapClusterKind.shelter => Icons.home_work,
      _MapClusterKind.petShop => Icons.storefront,
      _MapClusterKind.observations => Icons.pets,
    };
    final decoration = isPlace
        ? BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withValues(alpha: 0.96),
                color.withValues(alpha: 0.72),
              ],
            ),
            shape: BoxShape.circle,
            border: Border.all(color: colors.surface, width: 3),
            boxShadow: const [
              BoxShadow(
                blurRadius: 7,
                color: Color(0x55000000),
                offset: Offset(0, 3),
              ),
            ],
          )
        : BoxDecoration(
            color: color.withValues(alpha: alert ? 0.94 : 0.88),
            shape: BoxShape.circle,
            border: Border.all(color: colors.surface, width: 2),
            boxShadow: const [
              BoxShadow(
                blurRadius: 5,
                color: Color(0x44000000),
                offset: Offset(0, 2),
              ),
            ],
          );
    return GestureDetector(
      onTap: onTap,
      child: DecoratedBox(
        decoration: decoration,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(icon, color: colors.onPrimary, size: isPlace ? 23 : 21),
            Positioned(
              right: 0,
              top: 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 1.5),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Text(
                    '$count',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
              ),
            ),
          ],
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

Future<void> _launchPlaceUri(Uri uri) async {
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

Uri _webUri(String value) {
  final parsed = Uri.tryParse(value);
  if (parsed != null && parsed.hasScheme) {
    return parsed;
  }
  return Uri.parse('https://$value');
}

Uri _telegramUri(String value) {
  final trimmed = value.trim();
  if (trimmed.startsWith('@')) {
    return Uri.parse('https://t.me/${trimmed.substring(1)}');
  }
  return _webUri(trimmed);
}

void _showCatSheet(
  BuildContext context,
  CatSummary cat,
  AppStrings strings, {
  required VoidCallback onOpenPost,
}) {
  final markerKind = mapMarkerKindForPostKind(cat.latestPostKind);
  final title = cat.name?.trim().isNotEmpty == true
      ? cat.name!.trim()
      : strings.unnamedCat;
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
                    backgroundColor: markerKind == MapMarkerKind.needsHelp
                        ? theme.colorScheme.tertiaryContainer
                        : theme.colorScheme.secondaryContainer,
                    child: Icon(
                      mapMarkerIconForKind(markerKind),
                      color: markerKind == MapMarkerKind.needsHelp
                          ? theme.colorScheme.onTertiaryContainer
                          : theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(title, style: theme.textTheme.titleLarge),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                markerKind == MapMarkerKind.needsHelp
                    ? strings.needsHelp
                    : strings.observation,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  onOpenPost();
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
  MushukistanApi api,
) {
  final markerPlace = place;
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      return FutureBuilder<PlaceSummary>(
        future: api.getPlace(markerPlace.id),
        initialData: markerPlace,
        builder: (sheetContext, snapshot) {
          final place = snapshot.data ?? markerPlace;
          final publicPhone = publicPhoneUri(place.phone) != null
              ? place.phone
              : publicPhoneUri(place.phone2) != null
                  ? place.phone2
                  : null;
          final theme = Theme.of(sheetContext);
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.8,
              ),
              child: SingleChildScrollView(
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
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final category in place.categories)
                          _PlaceCategoryChip(
                            label: _placeCategoryLabel(category, strings),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    MarkerDetailActions(
                      strings: strings,
                      destination: place.location,
                      publicPhone: publicPhone,
                      showRoute: _placeSupportsRoute(place.category),
                    ),
                    if (place.address != null) ...[
                      const SizedBox(height: 12),
                      _PlaceDetailRow(
                        icon: Icons.place_outlined,
                        text: place.address!,
                      ),
                    ],
                    if (place.phone != null &&
                        publicPhoneUri(place.phone) != null) ...[
                      const SizedBox(height: 8),
                      _PlaceDetailRow(
                        icon: Icons.phone_outlined,
                        text: place.phone!,
                        onTap: () => unawaited(
                          launchPublicPhone(
                            sheetContext,
                            phone: place.phone!,
                            strings: strings,
                          ),
                        ),
                      ),
                    ],
                    if (place.phone2 != null &&
                        publicPhoneUri(place.phone2) != null) ...[
                      const SizedBox(height: 8),
                      _PlaceDetailRow(
                        icon: Icons.phone_outlined,
                        text: place.phone2!,
                        onTap: () => unawaited(
                          launchPublicPhone(
                            sheetContext,
                            phone: place.phone2!,
                            strings: strings,
                          ),
                        ),
                      ),
                    ],
                    if (place.openingHours != null) ...[
                      const SizedBox(height: 8),
                      _PlaceDetailRow(
                        icon: Icons.schedule_outlined,
                        text: place.openingHours!,
                      ),
                    ],
                    if (place.daysOff != null) ...[
                      const SizedBox(height: 8),
                      _PlaceDetailRow(
                        icon: Icons.event_busy_outlined,
                        text: place.daysOff!,
                      ),
                    ],
                    if (place.website != null) ...[
                      const SizedBox(height: 8),
                      _PlaceDetailRow(
                        icon: Icons.language_outlined,
                        text: place.website!,
                        onTap: () => unawaited(
                          _launchPlaceUri(_webUri(place.website!)),
                        ),
                      ),
                    ],
                    if (place.instagram != null) ...[
                      const SizedBox(height: 8),
                      _PlaceDetailRow(
                        icon: Icons.camera_alt_outlined,
                        text: place.instagram!,
                        onTap: () => unawaited(
                          _launchPlaceUri(_webUri(place.instagram!)),
                        ),
                      ),
                    ],
                    if (place.telegram != null) ...[
                      const SizedBox(height: 8),
                      _PlaceDetailRow(
                        icon: Icons.send_outlined,
                        text: place.telegram!,
                        onTap: () => unawaited(
                          _launchPlaceUri(_telegramUri(place.telegram!)),
                        ),
                      ),
                    ],
                    if (place.description != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        place.description!,
                        style: theme.textTheme.bodyMedium,
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
            ),
          );
        },
      );
    },
  );
}

void _showLostPetSheet(
  BuildContext context,
  LostPetMapData lostPet,
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

double _shortestRotationDelta(double current, double target) {
  var delta = (target - current) % 360;
  if (delta > 180) {
    delta -= 360;
  } else if (delta < -180) {
    delta += 360;
  }
  return delta;
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
            icon: mapMarkerIconForKind(MapMarkerKind.lostPet),
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
    required this.needsHelp,
    required this.onTap,
  });

  final bool needsHelp;
  final VoidCallback onTap;

  Color _color(BuildContext context) {
    return needsHelp
        ? Theme.of(context).colorScheme.tertiary
        : Theme.of(context).colorScheme.secondary;
  }

  @override
  Widget build(BuildContext context) {
    final color = _color(context);
    final markerKind =
        needsHelp ? MapMarkerKind.needsHelp : MapMarkerKind.observation;
    final icon = mapMarkerIconForKind(markerKind);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(
              icon,
              color: Theme.of(context).colorScheme.surface,
              size: 31,
            ),
            _MarkerIcon(
              icon: icon,
              color: color,
              size: 26,
            ),
          ],
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
    final icon = _icon;
    final colors = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.16),
          shape: BoxShape.circle,
          border: Border.all(color: color.withValues(alpha: 0.7), width: 2),
          boxShadow: const [
            BoxShadow(
              blurRadius: 7,
              color: Color(0x44000000),
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: colors.surface, width: 1.5),
            ),
            child: Center(
              child: _MarkerIcon(
                icon: icon,
                color: colors.onPrimary,
                size: 19,
              ),
            ),
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
              icon: mapMarkerIconForKind(MapMarkerKind.lostPet),
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
    required this.strings,
    required this.onPressed,
  });

  final AppStrings strings;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return _MapControlButton(
      tooltip: strings.filters,
      icon: Icons.tune,
      onPressed: onPressed,
    );
  }
}

class _MapControlButton extends StatelessWidget {
  const _MapControlButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      elevation: 2,
      borderRadius: BorderRadius.circular(8),
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: SizedBox.square(
            dimension: 48,
            child: Icon(icon, color: colors.onSurface),
          ),
        ),
      ),
    );
  }
}

String _layerLabel(_MapLayer layer, AppStrings strings) {
  return switch (layer) {
    _MapLayer.observations => strings.cats,
    _MapLayer.needsHelp => strings.needsHelp,
    _MapLayer.lostPets => strings.lostPets,
    _MapLayer.vets => strings.vets,
    _MapLayer.shops => strings.shops,
    _MapLayer.shelters => strings.shelters,
  };
}

String _placeCategoryLabel(String category, AppStrings strings) {
  return switch (category) {
    'veterinary' => strings.vets,
    'shelter' => strings.shelters,
    _ => strings.shops,
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

class _PlaceCategoryChip extends StatelessWidget {
  const _PlaceCategoryChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: colorScheme.onSecondaryContainer,
              ),
        ),
      ),
    );
  }
}

class _PlaceDetailRow extends StatelessWidget {
  const _PlaceDetailRow({
    required this.icon,
    required this.text,
    this.onTap,
  });

  final IconData icon;
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
    if (onTap == null) {
      return row;
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: row,
    );
  }
}

class _MapLoadError extends StatelessWidget {
  const _MapLoadError({
    required this.message,
    required this.retryLabel,
    required this.onRetry,
  });

  final String message;
  final String retryLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 2,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.only(left: 12),
        child: Row(
          children: [
            const Icon(Icons.error_outline, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child:
                  Text(message, maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
            TextButton(onPressed: onRetry, child: Text(retryLabel)),
          ],
        ),
      ),
    );
  }
}

// ignore: unused_element
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

// ignore: unused_element
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
