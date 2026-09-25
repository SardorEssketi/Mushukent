import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';
import 'package:mushukistan_frontend/features/profile/presentation/screens/edit_profile_screen.dart';
import 'package:mushukistan_frontend/features/profile/presentation/screens/profile_screen.dart';

import '../../support/fakes.dart';

void main() {
  testWidgets('avatar is not uploaded again when later profile save fails',
      (tester) async {
    final originalPicker = ImagePickerPlatform.instance;
    ImagePickerPlatform.instance = _AvatarPicker();
    addTearDown(() => ImagePickerPlatform.instance = originalPicker);

    final client = FakeApiClient();
    client.setHandler('POST', 'users/me/avatar', (call) {
      final photo = (call.body! as FormData).files.single.value;
      expect(photo.filename, 'avatar.png');
      expect(photo.contentType.toString(), 'image/png');
      return _profilePayload();
    });
    client.setHandler(
        'PATCH', 'users/me', (_) => throw StateError('save failed'));
    final container = ProviderContainer(overrides: [
      mushukistanApiProvider.overrideWithValue(MushukistanApi(client: client)),
      profileMeProvider.overrideWith(
          (ref) async => UserProfileData.fromJson(_profilePayload())),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: EditProfileScreen()),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Change profile picture'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Save changes'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(
      find.text(
          'Profile photo was saved, but other changes were not. Try again.'),
      findsOneWidget,
    );
    expect(client.calls.where((call) => call.path == 'users/me/avatar'),
        hasLength(1));

    await tester.drag(find.byType(ListView), const Offset(0, -150));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(client.calls.where((call) => call.path == 'users/me/avatar'),
        hasLength(1));
    expect(client.calls.where((call) => call.path == 'users/me'), hasLength(2));
  });
}

Map<String, Object?> _profilePayload() => <String, Object?>{
      'id': '11111111-1111-4111-8111-111111111111',
      'email': 'test@example.com',
      'registered_at': '2026-01-01T00:00:00Z',
      'observation_count': 0,
      'total_likes_received': 0,
      'comment_count': 0,
    };

class _AvatarPicker extends ImagePickerPlatform {
  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    final avatar = image.Image(width: 32, height: 32, numChannels: 4)
      ..setPixelRgba(0, 0, 200, 100, 50, 120);
    return XFile.fromData(
      Uint8List.fromList(image.encodePng(avatar)),
      path: 'avatar.png',
      name: 'avatar.png',
      mimeType: 'image/png',
    );
  }
}
