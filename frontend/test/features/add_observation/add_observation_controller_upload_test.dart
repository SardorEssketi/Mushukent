import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/core/localization/app_strings.dart';
import 'package:mushukistan_frontend/core/localization/language_controller.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';
import 'package:mushukistan_frontend/features/add_observation/application/add_observation_controller.dart';

import '../../support/fakes.dart';

void main() {
  Map<String, Object?> createdPost(String kind, GeoPoint? location) => {
        'id': 'post-1',
        'cat': {'id': 'cat-1', 'status': 'unknown', 'name': 'Mimi'},
        'photo_url': 'https://example.com/cat.jpg',
        'photo_urls': ['https://example.com/cat.jpg'],
        'location': location?.toJson(),
        'kind': kind,
        'created_at': '2026-10-01T00:00:00Z',
        'like_count': 0,
        'comment_count': 0,
        'is_liked_by_me': false,
      };

  test('normal post sends optional name and note without location', () async {
    final client = FakeApiClient();
    client.setHandler('POST', 'posts', (_) => createdPost('observation', null));
    final controller = AddObservationController(MushukistanApi(client: client));
    controller.setPhoto(
      bytes: Uint8List.fromList([0xff, 0xd8, 0xff, 0xd9]),
      filename: 'cat.jpg',
      contentType: 'image/jpeg',
    );
    controller.setCatName('  Mimi  ');
    controller.setDescription('  Sleeping in the sun  ');
    await controller.submit(
        strings: AppStrings.forLanguage(AppLanguage.english));
    final form = client.calls.single.body as FormData;
    final fields = Map.fromEntries(form.fields);
    expect(fields['kind'], 'observation');
    expect(fields.containsKey('location'), isFalse);
    expect(jsonDecode(fields['new_cat']!), {'name': 'Mimi'});
    expect(fields['description'], 'Sleeping in the sun');
    expect(form.files, hasLength(1));
  });

  test('help post requires location and nonblank help details', () async {
    final client = FakeApiClient();
    const location = GeoPoint(latitude: 41.31, longitude: 69.28);
    client.setHandler(
        'POST', 'posts', (_) => createdPost('needs_help', location));
    final controller = AddObservationController(MushukistanApi(client: client));
    controller.reset(kind: 'needs_help');
    controller.setPhoto(
      bytes: Uint8List.fromList([0xff, 0xd8, 0xff, 0xd9]),
      filename: 'cat.jpg',
      contentType: 'image/jpeg',
    );
    final strings = AppStrings.forLanguage(AppLanguage.english);
    await expectLater(controller.submit(strings: strings), throwsStateError);
    controller.setLocation(location);
    await expectLater(controller.submit(strings: strings), throwsStateError);
    controller.setDescription('  Injured paw  ');
    await controller.submit(strings: strings);
    final fields =
        Map.fromEntries((client.calls.single.body as FormData).fields);
    expect(fields['kind'], 'needs_help');
    expect(jsonDecode(fields['location']!), location.toJson());
    expect(fields['description'], 'Injured paw');
  });

  test('a second submit cannot start another photo upload', () async {
    final client = FakeApiClient();
    final pending = Completer<Object?>();
    client.setHandler('POST', 'posts', (_) => pending.future);
    final controller = AddObservationController(MushukistanApi(client: client));
    controller.setPhoto(
      bytes: Uint8List.fromList(<int>[0xff, 0xd8, 0xff, 0xd9]),
      filename: 'cat.jpg',
      contentType: 'image/jpeg',
    );

    final strings = AppStrings.forLanguage(AppLanguage.english);
    final first = controller.submit(strings: strings);
    expect(controller.state.submitting, isTrue);

    await expectLater(
      controller.submit(strings: strings),
      throwsStateError,
    );
    expect(client.calls, hasLength(1));

    final firstExpectation = expectLater(first, throwsStateError);
    pending.completeError(StateError('simulated network failure'));
    await firstExpectation;
    expect(controller.state.submitting, isFalse);
  });
}
