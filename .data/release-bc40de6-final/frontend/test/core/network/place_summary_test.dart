import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';

void main() {
  test('PlaceSummary parses extended nullable place fields', () {
    final place = PlaceSummary.fromJson(<String, Object?>{
      'id': 'place-1',
      'name': 'PetZoo',
      'category': 'veterinary',
      'categories': <Object?>['veterinary', 'pet_shop'],
      'location': <String, Object?>{
        'latitude': 41.300642,
        'longitude': 69.264158,
      },
      'address': 'улица Сарабустан, 3А/2',
      'phone': '+998 77 095 07 70',
      'phone_2': '+998 71 277 66 88',
      'instagram': 'https://www.instagram.com/petzoo.uz/',
      'telegram': 'https://t.me/aquamarine_zoo',
      'opening_hours': '10:00-20:00',
      'days_off': 'sun',
      'website': 'petzoo.uz',
      'description': 'Зоомагазин',
      'source': 'manual',
      'source_id': 'manual_file:abc',
    });

    expect(place.category, 'veterinary');
    expect(place.categories, <String>['veterinary', 'pet_shop']);
    expect(place.phone2, '+998 71 277 66 88');
    expect(place.instagram, 'https://www.instagram.com/petzoo.uz/');
    expect(place.telegram, 'https://t.me/aquamarine_zoo');
    expect(place.daysOff, 'sun');
    expect(place.description, 'Зоомагазин');
  });

  test('PlaceSummary falls back to single legacy category', () {
    final place = PlaceSummary.fromJson(<String, Object?>{
      'id': 'place-1',
      'name': 'PetZoo',
      'category': 'pet_shop',
      'location': <String, Object?>{
        'latitude': 41.300642,
        'longitude': 69.264158,
      },
      'source': 'manual',
    });

    expect(place.category, 'pet_shop');
    expect(place.categories, <String>['pet_shop']);
  });
}
