import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/core/localization/app_strings.dart';
import 'package:mushukistan_frontend/core/localization/language_controller.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';
import 'package:mushukistan_frontend/features/add_observation/application/add_observation_controller.dart';

import '../../support/fakes.dart';

void main() {
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
