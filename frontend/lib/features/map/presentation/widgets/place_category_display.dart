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
