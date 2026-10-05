import 'package:flutter/material.dart';

enum MapMarkerVisualKind {
  observations,
  needsHelp,
  lostPets,
  veterinary,
  veterinaryPharmacy,
  petShop,
  shelter,
}

bool _isPlace(MapMarkerVisualKind kind) => switch (kind) {
      MapMarkerVisualKind.veterinary ||
      MapMarkerVisualKind.veterinaryPharmacy ||
      MapMarkerVisualKind.petShop ||
      MapMarkerVisualKind.shelter =>
        true,
      _ => false,
    };

bool _isUrgent(MapMarkerVisualKind kind) =>
    kind == MapMarkerVisualKind.needsHelp ||
    kind == MapMarkerVisualKind.lostPets;

IconData mapVisualIcon(MapMarkerVisualKind kind) => switch (kind) {
      MapMarkerVisualKind.observations => Icons.pets_rounded,
      MapMarkerVisualKind.needsHelp => Icons.warning_amber_rounded,
      MapMarkerVisualKind.lostPets => Icons.search_rounded,
      MapMarkerVisualKind.veterinary => Icons.medical_services_rounded,
      MapMarkerVisualKind.veterinaryPharmacy => Icons.local_pharmacy_rounded,
      MapMarkerVisualKind.petShop => Icons.storefront_rounded,
      MapMarkerVisualKind.shelter => Icons.home_rounded,
    };

Color mapVisualAccent(MapMarkerVisualKind kind, ColorScheme colors) =>
    switch (kind) {
      MapMarkerVisualKind.observations => colors.secondary,
      MapMarkerVisualKind.needsHelp => colors.tertiary,
      MapMarkerVisualKind.lostPets => colors.error,
      MapMarkerVisualKind.veterinary => colors.primary,
      MapMarkerVisualKind.veterinaryPharmacy => colors.primary,
      MapMarkerVisualKind.petShop => colors.tertiary,
      MapMarkerVisualKind.shelter => colors.secondary,
    };

Color _fill(MapMarkerVisualKind kind, ColorScheme colors) => switch (kind) {
      MapMarkerVisualKind.needsHelp => colors.tertiaryContainer,
      MapMarkerVisualKind.lostPets => colors.errorContainer,
      _ => colors.surface,
    };

Color _ink(MapMarkerVisualKind kind, ColorScheme colors) => switch (kind) {
      MapMarkerVisualKind.needsHelp => colors.onTertiaryContainer,
      MapMarkerVisualKind.lostPets => colors.onErrorContainer,
      _ => mapVisualAccent(kind, colors),
    };

class MapMarkerVisual extends StatelessWidget {
  const MapMarkerVisual({
    super.key,
    required this.kind,
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  final MapMarkerVisualKind kind;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final place = _isPlace(kind);
    final radius = BorderRadius.circular(place ? 11 : 24);
    final accent = mapVisualAccent(kind, colors);
    final graphicSize = _isUrgent(kind) ? 36.0 : 33.0;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Tooltip(
        message: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Center(
            child: Container(
              width: selected ? 44 : graphicSize,
              height: selected ? 44 : graphicSize,
              alignment: Alignment.center,
              decoration: selected
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(place ? 15 : 24),
                      border: Border.all(color: accent, width: 2),
                    )
                  : null,
              child: Container(
                key: const ValueKey('map-marker-graphic'),
                width: graphicSize,
                height: graphicSize,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _fill(kind, colors),
                  borderRadius: radius,
                  border: Border.all(
                    color: _isUrgent(kind)
                        ? accent.withValues(alpha: 0.75)
                        : colors.outlineVariant,
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: colors.shadow.withValues(alpha: 0.22),
                      blurRadius: 5,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(mapVisualIcon(kind),
                    color: _ink(kind, colors), size: 20),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MapClusterVisual extends StatelessWidget {
  const MapClusterVisual({
    super.key,
    required this.kind,
    required this.label,
    required this.count,
    required this.onTap,
  });

  final MapMarkerVisualKind kind;
  final String label;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final accent = mapVisualAccent(kind, colors);
    return Semantics(
      button: true,
      label: '$label: $count',
      child: Tooltip(
        message: '$label: $count',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Center(
            child: Container(
              key: const ValueKey('map-cluster-graphic'),
              constraints: const BoxConstraints(minWidth: 46, minHeight: 34),
              padding: const EdgeInsets.symmetric(horizontal: 7),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: accent, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: colors.shadow.withValues(alpha: 0.23),
                    blurRadius: 5,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(mapVisualIcon(kind), color: accent, size: 16),
                  const SizedBox(width: 4),
                  Text('$count',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: colors.onSurface,
                          fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
