import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/core/localization/app_strings.dart';
import 'package:mushukistan_frontend/core/localization/language_controller.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';
import 'package:mushukistan_frontend/features/map/presentation/widgets/map_marker_visual.dart';
import 'package:mushukistan_frontend/features/map/presentation/widgets/place_category_display.dart';

void main() {
  const categories = <String>{
    'pet_shop',
    'veterinary',
    'veterinary_pharmacy',
    'shelter',
  };

  test('all four categories parse and respect independent map filters', () {
    expect(mapPlaceCategories, categories);
    for (final category in categories) {
      final place = PlaceSummary.fromJson({
        'id': 'e5389fba-e404-472b-9dc2-5ae420db9f67',
        'name': 'Example',
        'category': category,
        'categories': [category],
        'location': {'latitude': 41.3, 'longitude': 69.3},
        'source': 'manual',
      });
      expect(place.category, category);
      expect(place.categories, [category]);
      expect(isMapPlaceCategoryVisible({category}, place.category), isTrue);
      expect(
          isMapPlaceCategoryVisible(
              categories.difference({category}), place.category),
          isFalse);
    }
    expect(isMapPlaceCategoryVisible(categories, 'unknown'), isFalse);
  });

  test('four categories have separate marker kinds and localized labels', () {
    final kinds = categories.map(mapPlaceMarkerKind).toSet();
    expect(kinds, hasLength(4));
    expect(mapVisualIcon(MapMarkerVisualKind.veterinaryPharmacy),
        isNot(mapVisualIcon(MapMarkerVisualKind.veterinary)));
    for (final language in AppLanguage.values) {
      final strings = AppStrings.forLanguage(language);
      final labels = categories
          .map((category) => mapPlaceCategoryLabel(category, strings))
          .toSet();
      expect(labels, hasLength(4));
      expect(labels.every((label) => label.isNotEmpty), isTrue);
    }
  });

  test('empty shelter data does not affect other category behavior', () {
    final places = <PlaceSummary>[];
    expect(places.where((place) => place.category == 'shelter'), isEmpty);
    expect(isMapPlaceCategoryVisible({'shelter'}, 'shelter'), isTrue);
    expect(mapPlaceMarkerKind('shelter'), MapMarkerVisualKind.shelter);
  });
}
