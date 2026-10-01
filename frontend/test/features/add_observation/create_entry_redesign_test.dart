import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as image;
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:mushukistan_frontend/core/localization/app_strings.dart';
import 'package:mushukistan_frontend/core/localization/language_controller.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';
import 'package:mushukistan_frontend/features/add_observation/application/add_observation_controller.dart';
import 'package:mushukistan_frontend/features/add_observation/presentation/screens/add_observation_screen.dart';

import '../../support/fakes.dart';

Map<String, Object?> _profile({String? phone}) => {
      'id': 'owner-one',
      'email': 'owner@example.com',
      'name': 'Owner',
      'phone_number': phone,
      'registered_at': '2026-01-01T00:00:00Z',
      'observation_count': 0,
      'total_likes_received': 0,
      'comment_count': 0,
    };

void _size(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<(ProviderContainer, GoRouter)> _mount(
  WidgetTester tester,
  FakeApiClient client, {
  AppLanguage language = AppLanguage.english,
}) async {
  final container = ProviderContainer(overrides: [
    mushukistanApiProvider.overrideWithValue(MushukistanApi(client: client)),
    appLanguageProvider.overrideWith((ref) => language),
  ]);
  addTearDown(container.dispose);
  final router = GoRouter(initialLocation: '/add', routes: [
    GoRoute(
      path: '/add',
      builder: (_, __) => const AddObservationScreen(),
      routes: [
        GoRoute(
            path: 'location',
            builder: (_, __) => Consumer(builder: (context, ref, child) {
                  final state = ref.watch(addObservationControllerProvider);
                  return Scaffold(body: Text('Location kind: ${state.kind}'));
                })),
        GoRoute(
            path: 'lost-pet',
            builder: (_, __) => const Scaffold(body: Text('Lost Pet form'))),
        GoRoute(
            path: 'adoption',
            builder: (_, __) => const Scaffold(body: Text('Rehoming form'))),
      ],
    ),
    GoRoute(
        path: '/profile/edit',
        builder: (_, __) => const Scaffold(body: Text('Edit Profile route'))),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return (container, router);
}

void main() {
  testWidgets('Create shows four cards in a compact wide grid', (tester) async {
    _size(tester, 1280);
    await _mount(tester, FakeApiClient());
    expect(find.text('Cat observation'), findsOneWidget);
    expect(find.text('Needs help'), findsOneWidget);
    expect(find.text('Lost Pet'), findsOneWidget);
    expect(find.text('Find a new home'), findsOneWidget);
    expect(
        find.text('Choose the kind of cat help or update you want to share.'),
        findsOneWidget);
    final first = tester.getTopLeft(find.text('Cat observation'));
    final second = tester.getTopLeft(find.text('Needs help'));
    final third = tester.getTopLeft(find.text('Lost Pet'));
    expect((first.dy - second.dy).abs(), lessThan(2));
    expect(second.dx, greaterThan(first.dx));
    expect(third.dy, greaterThan(first.dy));
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile stacks cards and translated copy stays in bounds',
      (tester) async {
    _size(tester, 360);
    for (final (width, language) in [
      (360.0, AppLanguage.english),
      (800.0, AppLanguage.russian),
      (1280.0, AppLanguage.uzbek),
      (1700.0, AppLanguage.english),
    ]) {
      tester.view.physicalSize = Size(width, 900);
      await tester.pumpWidget(ProviderScope(
        key: ValueKey('$width-${language.code}'),
        overrides: [
          appLanguageProvider.overrideWith((ref) => language),
        ],
        child: const MaterialApp(home: AddObservationScreen()),
      ));
      await tester.pumpAndSettle();
      if (width == 360) {
        expect(tester.getTopLeft(find.text('Needs help')).dy,
            greaterThan(tester.getTopLeft(find.text('Cat observation')).dy));
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('dark compact layout supports larger Russian text',
      (tester) async {
    _size(tester, 360);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appLanguageProvider.overrideWith((ref) => AppLanguage.russian),
      ],
      child: MaterialApp(
        theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: const AddObservationScreen(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Observation gallery keeps five-photo limit and kind',
      (tester) async {
    _size(tester, 800);
    final original = ImagePickerPlatform.instance;
    final picker = _EntryPicker();
    ImagePickerPlatform.instance = picker;
    addTearDown(() => ImagePickerPlatform.instance = original);
    final (container, _) = await _mount(tester, FakeApiClient());
    await tester.tap(find.text('Cat observation'));
    await tester.pumpAndSettle();
    expect(find.text('Choose from gallery'), findsOneWidget);
    expect(find.text('Take a photo'), findsOneWidget);
    await tester.tap(find.text('Choose from gallery'));
    await tester.pumpAndSettle();
    expect(picker.galleryCalls, 1);
    expect(picker.lastLimit, 5);
    expect(find.text('Location kind: observation'), findsOneWidget);
    expect(
        container.read(addObservationControllerProvider).photos, hasLength(1));
  });

  testWidgets('Needs help camera keeps needs_help kind', (tester) async {
    _size(tester, 800);
    final original = ImagePickerPlatform.instance;
    final picker = _EntryPicker();
    ImagePickerPlatform.instance = picker;
    addTearDown(() => ImagePickerPlatform.instance = original);
    final (container, _) = await _mount(tester, FakeApiClient());
    await tester.tap(find.text('Needs help'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Take a photo'));
    await tester.pumpAndSettle();
    expect(picker.cameraCalls, 1);
    expect(find.text('Location kind: needs_help'), findsOneWidget);
    expect(container.read(addObservationControllerProvider).kind, 'needs_help');
  });

  testWidgets('Lost Pet and Rehoming require valid phone before opening forms',
      (tester) async {
    _size(tester, 800);
    final client = FakeApiClient();
    client.setHandler('GET', 'users/me', (_) => _profile(phone: '12345'));
    await _mount(tester, client);
    await tester.tap(find.text('Lost Pet'));
    await tester.pumpAndSettle();
    expect(
        find.text(AppStrings.forLanguage(AppLanguage.english)
            .phoneNumberRequiredForLostPet),
        findsOneWidget);
    expect(find.text('Lost Pet form'), findsNothing);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Find a new home'));
    await tester.pumpAndSettle();
    expect(
        find.text(AppStrings.forLanguage(AppLanguage.english)
            .phoneNumberRequiredForAdoption),
        findsOneWidget);
    expect(find.text('Rehoming form'), findsNothing);
    await tester.tap(find.text('Edit profile'));
    await tester.pumpAndSettle();
    expect(find.text('Edit Profile route'), findsOneWidget);
  });

  testWidgets('valid contact opens each matching create route', (tester) async {
    _size(tester, 800);
    final client = FakeApiClient();
    client.setHandler(
        'GET', 'users/me', (_) => _profile(phone: '+998 90 123 4567'));
    final (_, router) = await _mount(tester, client);
    await tester.tap(find.text('Lost Pet'));
    await tester.pumpAndSettle();
    expect(find.text('Lost Pet form'), findsOneWidget);
    router.go('/add');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Find a new home'));
    await tester.pumpAndSettle();
    expect(find.text('Rehoming form'), findsOneWidget);
  });

  testWidgets('draft is separate, continues with photo, and deletes on confirm',
      (tester) async {
    _size(tester, 800);
    final (container, router) = await _mount(tester, FakeApiClient());
    final controller =
        container.read(addObservationControllerProvider.notifier);
    controller.setPhoto(
        bytes: Uint8List.fromList([1, 2, 3]),
        filename: 'draft.jpg',
        contentType: 'image/jpeg');
    await tester.pumpAndSettle();
    expect(find.text('Continue draft'), findsOneWidget);
    expect(find.text('Delete draft'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Location kind: observation'), findsOneWidget);
    router.go('/add');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete draft'));
    await tester.pumpAndSettle();
    expect(find.text('Delete draft?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(container.read(addObservationControllerProvider).hasDraft, isTrue);
    await tester.tap(find.text('Delete draft'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(container.read(addObservationControllerProvider).hasDraft, isFalse);
    expect(find.text('Draft deleted.'), findsOneWidget);
    expect(find.text('Continue draft'), findsNothing);
  });

  testWidgets('draft without a photo cannot enter the location step',
      (tester) async {
    _size(tester, 800);
    final (container, _) = await _mount(tester, FakeApiClient());
    container
        .read(addObservationControllerProvider.notifier)
        .setDescription('Unfinished description');
    await tester.pumpAndSettle();
    expect(find.text('Continue draft'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Continue'))
            .onPressed,
        isNull);
  });

  testWidgets('pending photo preparation prevents another picker action',
      (tester) async {
    _size(tester, 800);
    final original = ImagePickerPlatform.instance;
    final picker = _EntryPicker(delayed: true);
    ImagePickerPlatform.instance = picker;
    addTearDown(() => ImagePickerPlatform.instance = original);
    await _mount(tester, FakeApiClient());
    await tester.tap(find.text('Cat observation'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose from gallery'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Preparing photo for upload...'), findsOneWidget);
    expect(find.text('Add cat photos'), findsNothing);
    await tester.tap(find.text('Needs help'));
    await tester.pump();
    expect(picker.galleryCalls, 1);
    expect(find.text('Add cat photos'), findsNothing);
    picker.completeDelayed();
    await tester.pumpAndSettle();
    expect(find.text('Location kind: observation'), findsOneWidget);
  });
}

class _EntryPicker extends ImagePickerPlatform {
  _EntryPicker({this.delayed = false});

  final bool delayed;
  int galleryCalls = 0;
  int cameraCalls = 0;
  int? lastLimit;
  final Completer<Uint8List> _pendingBytes = Completer<Uint8List>();

  Uint8List _png() {
    final photo = image.Image(width: 32, height: 32)
      ..setPixelRgb(0, 0, 200, 100, 50);
    return Uint8List.fromList(image.encodePng(photo));
  }

  @override
  Future<List<XFile>> getMultiImageWithOptions({
    MultiImagePickerOptions options = const MultiImagePickerOptions(),
  }) async {
    galleryCalls++;
    lastLimit = options.limit;
    if (delayed) {
      return [_DelayedXFile(_pendingBytes)];
    }
    return [XFile.fromData(_png(), name: 'cat.png', mimeType: 'image/png')];
  }

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    cameraCalls++;
    return XFile.fromData(_png(), name: 'cat.png', mimeType: 'image/png');
  }

  void completeDelayed() => _pendingBytes.complete(_png());
}

class _DelayedXFile extends XFile {
  _DelayedXFile(this.pending) : super('delayed.png');

  final Completer<Uint8List> pending;

  @override
  Future<int> length() async => 1024;

  @override
  Future<Uint8List> readAsBytes() => pending.future;
}
