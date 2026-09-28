import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';

import '../../support/fakes.dart';

Map<String, Object?> _lostPetPayload({
  String petName = 'Updated Mittens',
  bool resolved = false,
}) =>
    {
      'id': 'pet-1',
      'pet_name': petName,
      'owner_phone_number': '+998 91 234 5678',
      'owner_telegram_username': 'mittens_owner',
      'photo_url': 'https://example.com/pet.jpg',
      'photo_urls': ['https://example.com/pet.jpg'],
      'last_seen_location': {'latitude': 41.31, 'longitude': 69.26},
      'additional_info': 'Near the park',
      'created_at': '2026-09-28T09:00:00Z',
      'is_resolved': resolved,
      'comment_count': 0,
    };

void main() {
  test('updates only editable Lost Pet fields through owner endpoint',
      () async {
    final client = FakeApiClient();
    final api = MushukistanApi(client: client);
    client.setHandler('PATCH', 'lost-pets/pet-1', (call) {
      expect(call.authenticated, isTrue);
      expect(call.body, <String, Object?>{
        'pet_name': 'Updated Mittens',
        'owner_phone_number': '+998 91 234 5678',
        'owner_telegram_username': 'mittens_owner',
        'last_seen_location': {'latitude': 41.31, 'longitude': 69.26},
        'additional_info': 'Near the park',
      });
      return _lostPetPayload();
    });

    final updated = await api.updateLostPet(
      lostPetId: 'pet-1',
      petName: ' Updated Mittens ',
      phoneNumber: ' +998 91 234 5678 ',
      telegramUsername: '@mittens_owner',
      lastSeenLocation: const GeoPoint(latitude: 41.31, longitude: 69.26),
      additionalInfo: ' Near the park ',
    );

    expect(updated.petName, 'Updated Mittens');
    expect(updated.isResolved, isFalse);
  });

  test('replaces Lost Pet photos as multipart files', () async {
    final client = FakeApiClient();
    final api = MushukistanApi(client: client);
    client.setHandler('PATCH', 'lost-pets/pet-1', (call) {
      final formData = call.body! as FormData;
      final photos = formData.files
          .where((entry) => entry.key == 'photos')
          .map((entry) => entry.value)
          .toList(growable: false);
      expect(photos, hasLength(1));
      expect(photos.single.filename, 'replacement.jpg');
      expect(formData.fields.any((field) => field.key == 'pet_name'), isTrue);
      expect(
        formData.fields
            .firstWhere((field) => field.key == 'owner_telegram_username')
            .value,
        '',
      );
      return _lostPetPayload();
    });

    await api.updateLostPet(
      lostPetId: 'pet-1',
      petName: 'Updated Mittens',
      phoneNumber: '+998 91 234 5678',
      telegramUsername: null,
      lastSeenLocation: const GeoPoint(latitude: 41.31, longitude: 69.26),
      additionalInfo: 'Near the park',
      replacementPhotos: [
        LostPetPhotoUpload(
          bytes: Uint8List.fromList(<int>[1, 2, 3]),
          filename: 'replacement.jpg',
          contentType: 'image/jpeg',
        ),
      ],
    );
  });

  test('deletes a Lost Pet through authenticated owner endpoint', () async {
    final client = FakeApiClient();
    final api = MushukistanApi(client: client);
    client.setHandler('DELETE', 'lost-pets/pet-1', (call) {
      expect(call.authenticated, isTrue);
      return null;
    });

    await api.deleteLostPet('pet-1');

    expect(client.calls.single.method, 'DELETE');
  });
}
