import '../../../../core/localization/app_strings.dart';
import 'map_marker_visual.dart';

const mapPlaceCategories = <String>{
  'pet_shop',
  'veterinary',
  'veterinary_pharmacy',
  'shelter',
};

bool isMapPlaceCategoryVisible(
    Set<String> selectedCategories, String category) {
  return mapPlaceCategories.contains(category) &&
      selectedCategories.contains(category);
}

bool mapPlaceSupportsRoute(String category) =>
    category == 'pet_shop' ||
    category == 'veterinary' ||
    category == 'veterinary_pharmacy';

MapMarkerVisualKind mapPlaceMarkerKind(String category) => switch (category) {
      'veterinary' => MapMarkerVisualKind.veterinary,
      'veterinary_pharmacy' => MapMarkerVisualKind.veterinaryPharmacy,
      'shelter' => MapMarkerVisualKind.shelter,
      _ => MapMarkerVisualKind.petShop,
    };

String mapPlaceCategoryLabel(String category, AppStrings strings) =>
    switch (category) {
      'veterinary' => strings.vets,
      'veterinary_pharmacy' => strings.vetPharmacies,
      'shelter' => strings.shelters,
      _ => strings.shops,
    };

/// Singular type of one place ("veterinary clinic").
String mapPlaceTypeLabel(String category, AppStrings strings) =>
    switch (category) {
      'veterinary' => strings.placeTypeVeterinary,
      'veterinary_pharmacy' => strings.placeTypeVetPharmacy,
      'shelter' => strings.placeTypeShelter,
      _ => strings.placeTypePetShop,
    };

/// Accessible name of one place marker: the place's own name (unchanged,
/// never translated) and its type, so markers of one category stay distinct.
/// Clusters keep the category name with a count instead.
String mapPlaceMarkerLabel(
  String name,
  String category,
  AppStrings strings,
) {
  final type = mapPlaceTypeLabel(category, strings);
  final trimmed = name.trim();
  return trimmed.isEmpty ? type : '$trimmed, $type';
}
