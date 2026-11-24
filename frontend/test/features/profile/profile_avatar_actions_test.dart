import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:image_picker/image_picker.dart';
import 'package:mushukistan_frontend/core/network/api_error.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';
import 'package:mushukistan_frontend/features/auth/application/auth_controller.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_models.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_repository.dart';
import 'package:mushukistan_frontend/features/feed/presentation/screens/feed_screen.dart';
import 'package:mushukistan_frontend/features/profile/presentation/screens/profile_screen.dart';
import 'package:mushukistan_frontend/features/profile/presentation/widgets/avatar_crop_editor.dart';
import 'package:mushukistan_frontend/features/profile/presentation/widgets/profile_avatar_actions.dart';

import '../../support/exif_fixtures.dart';
import '../../support/fakes.dart';

Uint8List _png(int width, int height) =>
    image.encodePng(image.Image(width: width, height: height, numChannels: 4)
      ..clear(image.ColorRgba8(200, 120, 40, 255)));

class _Backend {
  _Backend({this.avatarUrl});
  String? avatarUrl;
  final client = FakeApiClient();
  final picked = <ImageSource>[];
  var cropCalls = 0;
  Uint8List? cropResult = _png(300, 300);
  Uint8List pickedBytes = _png(400, 300);
  final cropInputs = <Uint8List>[];
  var feedLoads = 0;
  late ProviderContainer container;

  Map<String, Object?> profile() => {
        'id': testUser().id,
        'email': 'owner@example.com',
        'name': 'Amina Catlover',
        'phone_number': '+998901234567',
        'avatar_url': avatarUrl,
        'registered_at': '2026-01-01T00:00:00Z',
        'observation_count': 1,
        'total_likes_received': 2,
        'comment_count': 3,
      };
}

Future<_Backend> _mount(
  WidgetTester tester, {
  String? avatarUrl,
  bool camera = true,
  bool withCachedUserProbe = false,
  void Function(_Backend backend)? before,
}) async {
  tester.view.physicalSize = const Size(800, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final backend = _Backend(avatarUrl: avatarUrl);
  before?.call(backend);
  backend.client.setHandler('GET', 'users/me', (_) => backend.profile());
  final container = ProviderContainer(overrides: [
    authRepositoryProvider.overrideWithValue(FakeAuthRepository(
      restoreResult: SessionRestoreSuccess(
        AuthSession.restored(
            accessToken: 'token', user: testUser(avatarUrl: avatarUrl)),
      ),
    )),
    googleIdentityTokenProvider
        .overrideWithValue(FakeGoogleIdentityTokenProvider()),
    mushukistanApiProvider
        .overrideWithValue(MushukistanApi(client: backend.client)),
    avatarCameraAvailableProvider.overrideWithValue(camera),
    avatarImagePickerProvider.overrideWithValue((source) async {
      backend.picked.add(source);
      return XFile.fromData(backend.pickedBytes,
          name: 'picked.jpg', mimeType: 'image/jpeg');
    }),
    avatarCropperProvider.overrideWithValue((context, bytes) async {
      backend.cropCalls++;
      backend.cropInputs.add(bytes);
      return backend.cropResult;
    }),
    // Stands in for the feed: counts loads so a refresh can be observed.
    feedPostsProvider.overrideWith((ref) async {
      ref.watch(postMutationRevisionProvider);
      backend.feedLoads++;
      return const ApiPage<FeedItem>(items: [], limit: 20);
    }),
  ]);
  addTearDown(container.dispose);
  backend.container = container;
  await container.read(authControllerProvider.notifier).restoreSession();
  final keepFeed = container.listen(feedPostsProvider, (_, __) {});
  addTearDown(keepFeed.close);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: withCachedUserProbe
          ? Column(children: [
              const Expanded(child: ProfileScreen()),
              // Another screen that reads the signed-in (cached) user.
              Consumer(
                builder: (context, ref, _) => Text(
                  'cached avatar: '
                  '${ref.watch(currentUserProvider)?.avatarUrl ?? 'none'}',
                  textDirection: TextDirection.ltr,
                ),
              ),
            ])
          : const ProfileScreen(),
    ),
  ));
  await tester.pumpAndSettle();
  return backend;
}

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('profile-avatar-button')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('avatar shows a camera badge and is a named button',
      (tester) async {
    await _mount(tester);
    expect(find.byIcon(Icons.photo_camera), findsOneWidget);
    expect(find.bySemanticsLabel('Change photo'), findsOneWidget);
  });

  testWidgets('with a photo the sheet offers open, gallery, camera, remove',
      (tester) async {
    await _mount(tester, avatarUrl: 'invalid:');
    await _openSheet(tester);
    expect(find.text('Profile photo'), findsOneWidget);
    expect(find.text('Open photo'), findsOneWidget);
    expect(find.text('Choose from gallery'), findsOneWidget);
    expect(find.text('Take photo'), findsOneWidget);
    expect(find.text('Remove photo'), findsOneWidget);
  });

  testWidgets('without a photo the sheet offers only gallery and camera',
      (tester) async {
    await _mount(tester);
    await _openSheet(tester);
    expect(find.text('Open photo'), findsNothing);
    expect(find.text('Remove photo'), findsNothing);
    expect(find.text('Choose from gallery'), findsOneWidget);
    expect(find.text('Take photo'), findsOneWidget);
  });

  testWidgets('no camera, no "Take photo"', (tester) async {
    await _mount(tester, avatarUrl: 'invalid:', camera: false);
    await _openSheet(tester);
    expect(find.text('Take photo'), findsNothing);
    expect(find.text('Choose from gallery'), findsOneWidget);
  });

  testWidgets('system back closes the sheet and stays on the profile',
      (tester) async {
    await _mount(tester);
    await _openSheet(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Choose from gallery'), findsNothing);
    expect(find.byType(ProfileScreen), findsOneWidget);
  });

  testWidgets('gallery photo is cropped, then only the crop is uploaded',
      (tester) async {
    final backend = await _mount(tester);
    backend.client.setHandler('POST', 'users/me/avatar', (call) {
      final upload = (call.body! as FormData).files.single.value;
      expect(upload.contentType.toString(), 'image/png');
      backend.avatarUrl = 'https://media.example/new.png';
      return backend.profile();
    });
    await _openSheet(tester);
    await tester.tap(find.text('Choose from gallery'));
    await tester.pumpAndSettle();

    expect(backend.picked, [ImageSource.gallery]);
    expect(backend.cropCalls, 1);
    final uploads = backend.client.calls
        .where(
            (call) => call.method == 'POST' && call.path == 'users/me/avatar')
        .toList();
    expect(uploads, hasLength(1));
    // The uploaded file is the 300x300 crop, not the 400x300 original.
    final file = (uploads.single.body! as FormData).files.single.value;
    final bytes = await tester.runAsync(() async {
      final chunks = await file.finalize().toList();
      return Uint8List.fromList(chunks.expand((c) => c).toList());
    });
    final decoded = image.decodeImage(bytes!)!;
    expect((decoded.width, decoded.height), (300, 300));
    expect(find.text('Photo updated.'), findsOneWidget);
    expect(
        backend.client.calls
            .where((call) => call.method == 'GET' && call.path == 'users/me'),
        hasLength(2));
  });

  testWidgets('camera choice uses the camera source', (tester) async {
    final backend = await _mount(tester);
    backend.client
        .setHandler('POST', 'users/me/avatar', (_) => backend.profile());
    await _openSheet(tester);
    await tester.tap(find.text('Take photo'));
    await tester.pumpAndSettle();
    expect(backend.picked, [ImageSource.camera]);
  });

  testWidgets('cancelling the crop uploads nothing', (tester) async {
    final backend = await _mount(tester);
    backend.cropResult = null;
    await _openSheet(tester);
    await tester.tap(find.text('Choose from gallery'));
    await tester.pumpAndSettle();
    expect(backend.cropCalls, 1);
    expect(
        backend.client.calls.where((call) => call.method == 'POST'), isEmpty);
  });

  testWidgets('upload failure shows the existing photo error', (tester) async {
    final backend = await _mount(tester);
    backend.client.setHandler(
        'POST',
        'users/me/avatar',
        (_) => throw const MushukistanApiException(
            kind: ApiFailureKind.validation,
            code: 'INVALID_IMAGE',
            message: 'bad'));
    await _openSheet(tester);
    await tester.tap(find.text('Choose from gallery'));
    await tester.pumpAndSettle();
    expect(find.text('Photo updated.'), findsNothing);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('remove asks first, then deletes and shows initials',
      (tester) async {
    final backend = await _mount(tester, avatarUrl: 'invalid:');
    backend.client.setHandler('DELETE', 'users/me/avatar', (_) {
      backend.avatarUrl = null;
      return null;
    });
    await _openSheet(tester);
    await tester.tap(find.text('Remove photo'));
    await tester.pumpAndSettle();
    expect(find.text('Remove profile photo?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(backend.client.calls.where((c) => c.method == 'DELETE'), isEmpty);

    await _openSheet(tester);
    await tester.tap(find.text('Remove photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(
        backend.client.calls.where((c) => c.method == 'DELETE'), hasLength(1));
    expect(find.text('Photo removed.'), findsOneWidget);
    expect(find.text('AC'), findsOneWidget);
    await _openSheet(tester);
    expect(find.text('Remove photo'), findsNothing);
  });

  testWidgets('open photo shows it full screen', (tester) async {
    await _mount(tester, avatarUrl: 'invalid:');
    await _openSheet(tester);
    await tester.tap(find.text('Open photo'));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);
    await tester.tap(find.byType(CloseButton));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsNothing);
  });

  testWidgets('a new or removed photo reaches the cached signed-in user',
      (tester) async {
    final backend = await _mount(tester,
        avatarUrl: 'https://media.example/old.png', withCachedUserProbe: true);
    backend.client.setHandler('POST', 'users/me/avatar', (_) {
      backend.avatarUrl = 'https://media.example/new.png';
      return backend.profile();
    });
    backend.client.setHandler('DELETE', 'users/me/avatar', (_) {
      backend.avatarUrl = null;
      return null;
    });
    expect(find.text('cached avatar: https://media.example/old.png'),
        findsOneWidget);
    final feedLoadsBefore = backend.feedLoads;

    await _openSheet(tester);
    await tester.tap(find.text('Choose from gallery'));
    await tester.pumpAndSettle();
    expect(find.text('cached avatar: https://media.example/new.png'),
        findsOneWidget);
    expect(backend.container.read(currentUserProvider)?.avatarUrl,
        'https://media.example/new.png');
    // Server data that embeds my avatar (feed authors) is fetched again.
    expect(backend.feedLoads, greaterThan(feedLoadsBefore));

    final feedLoadsAfterUpload = backend.feedLoads;
    await _openSheet(tester);
    await tester.tap(find.text('Remove photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('cached avatar: none'), findsOneWidget);
    expect(backend.container.read(currentUserProvider)?.hasAvatar, isFalse);
    expect(backend.feedLoads, greaterThan(feedLoadsAfterUpload));
  });

  for (final (orientation, portrait, redFirst) in [
    (3, false, false),
    (6, true, true),
    (8, true, false),
  ]) {
    testWidgets('EXIF orientation $orientation is shown and cropped upright',
        (tester) async {
      final backend = await _mount(tester,
          before: (b) => b.pickedBytes = exifOrientedJpeg(orientation));
      backend.cropResult = null;
      await _openSheet(tester);
      await tester.tap(find.text('Choose from gallery'));
      await tester.pumpAndSettle();

      // What the editor gets: pixels already upright, no EXIF tag left that
      // the platform decoder could apply a second time.
      final input = backend.cropInputs.single;
      expect(image.decodeJpgExif(input)?.imageIfd.orientation, isNull);
      final shown = (await tester.runAsync(() => decodeAvatarSource(input)))!;
      expect(shown.width < shown.height, portrait);
      // The crop of the default framing keeps that orientation.
      final png = (await tester.runAsync(() => renderAvatarCrop(
          AvatarCropView(
              imageSize: Size(shown.width.toDouble(), shown.height.toDouble()),
              diameter: 200),
          shown)))!;
      final crop = image.decodePng(png)!;
      final first = portrait
          ? crop.getPixel(crop.width ~/ 2, crop.height ~/ 8)
          : crop.getPixel(crop.width ~/ 8, crop.height ~/ 2);
      final last = portrait
          ? crop.getPixel(crop.width ~/ 2, crop.height * 7 ~/ 8)
          : crop.getPixel(crop.width * 7 ~/ 8, crop.height ~/ 2);
      expect(isRed(first), redFirst, reason: 'first half: $first');
      expect(isBlue(last), redFirst, reason: 'second half: $last');
      expect(isBlue(first), !redFirst);
      expect(isRed(last), !redFirst);
      shown.dispose();
    });
  }

  testWidgets('the editor decodes large photos at most 2048 px long',
      (tester) async {
    final sizes = await tester.runAsync(() async {
      final big = await decodeAvatarSource(
          image.encodePng(image.Image(width: 3000, height: 1000)));
      final small = await decodeAvatarSource(
          image.encodePng(image.Image(width: 800, height: 600)));
      final result = [big.width, big.height, small.width, small.height];
      big.dispose();
      small.dispose();
      return result;
    });
    expect(sizes, [2048, 683, 800, 600]);
    expect(avatarEditorMaxSide, 2048);
  });

  group('crop maths', () {
    const size = Size(400, 300);
    AvatarCropView view() =>
        const AvatarCropView(imageSize: size, diameter: 200);

    bool circleOnPhoto(AvatarCropView v) {
      final centre = v.imagePointAt(Offset.zero);
      final r = v.diameter / 2 / v.scale;
      return centre.dx.abs() + r <= size.width / 2 + 1e-6 &&
          centre.dy.abs() + r <= size.height / 2 + 1e-6;
    }

    test('starts with the short side filling the circle', () {
      expect(view().scale, closeTo(200 / 300, 1e-9));
      expect(view().outputSide, 300);
    });

    test('dragging stops at the photo edge', () {
      final dragged = view().gesture(
          startFocal: Offset.zero,
          focal: const Offset(-1000, 0),
          scaleFactor: 1,
          rotationDelta: 0);
      expect(circleOnPhoto(dragged), isTrue);
      expect(dragged.imagePointAt(Offset.zero).dx, closeTo(50, 1e-6));
    });

    test('zoom is limited and keeps the pinch point in place', () {
      final zoomed = view().gesture(
          startFocal: const Offset(20, 10),
          focal: const Offset(20, 10),
          scaleFactor: 2,
          rotationDelta: 0);
      expect(zoomed.zoom, 2);
      expect(zoomed.imagePointAt(const Offset(20, 10)).dx,
          closeTo(view().imagePointAt(const Offset(20, 10)).dx, 1e-6));
      expect(view().around(zoom: 50).zoom, AvatarCropView.maxZoom);
      expect(view().around(zoom: 0.1).zoom, 1);
    });

    test('rotation keeps the circle covered', () {
      final rotated = view().around(zoom: 1.5).gesture(
          startFocal: Offset.zero,
          focal: const Offset(500, -500),
          scaleFactor: 1,
          rotationDelta: math.pi / 5);
      expect(rotated.rotation, closeTo(math.pi / 5, 1e-9));
      expect(circleOnPhoto(rotated), isTrue);
    });
  });

  testWidgets('crop editor returns a square PNG on Done, null on Cancel',
      (tester) async {
    tester.view.physicalSize = const Size(600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final results = <Uint8List?>[];
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => results
                .add(await showAvatarCropEditor(context, _png(400, 300))),
            child: const Text('crop'),
          ),
        ),
      ),
    ));
    for (final action in ['Cancel', 'Done']) {
      await tester.tap(find.text('crop'));
      await tester.pump();
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('avatar-crop-area')), findsOneWidget);
      await tester.tap(find.byTooltip('Rotate'));
      await tester.pump();
      // Export renders on the engine, so it must run outside the fake clock.
      await tester.runAsync(() async => tester.tap(find.text(action)));
      for (var i = 0; i < 50 && find.text('crop').evaluate().isEmpty; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(find.text('crop'), findsOneWidget);
    }
    expect(results, hasLength(2));
    expect(results.first, isNull);
    final png = image.decodePng(results.last!)!;
    expect(png.width, png.height);
    expect(png.width, 300);
  });
}
