import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as image;
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:mushukistan_frontend/core/localization/language_controller.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';
import 'package:mushukistan_frontend/features/profile/presentation/screens/edit_profile_screen.dart';
import 'package:mushukistan_frontend/features/profile/presentation/screens/profile_screen.dart';

import '../../support/fakes.dart';

Map<String, Object?> _profile({String? avatarUrl}) => {
      'id': 'user-one',
      'email': 'private@example.com',
      'name': 'Amina Catlover',
      'phone_number': '+998 90 123 4567',
      'telegram_username': 'amina_cats',
      'bio': 'Helping neighborhood cats',
      'avatar_url': avatarUrl,
      'registered_at': '2026-01-01T00:00:00Z',
      'observation_count': 3,
      'total_likes_received': 4,
      'comment_count': 5,
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
  String? avatarUrl,
  AppLanguage language = AppLanguage.english,
}) async {
  final container = ProviderContainer(overrides: [
    mushukistanApiProvider.overrideWithValue(MushukistanApi(client: client)),
    profileMeProvider.overrideWith((ref) async =>
        UserProfileData.fromJson(_profile(avatarUrl: avatarUrl))),
    appLanguageProvider.overrideWith((ref) => language),
  ]);
  addTearDown(container.dispose);
  final router = GoRouter(initialLocation: '/profile/edit', routes: [
    GoRoute(
      path: '/profile',
      builder: (_, __) => const Scaffold(body: Text('Profile home')),
      routes: [
        GoRoute(path: 'edit', builder: (_, __) => const EditProfileScreen()),
      ],
    ),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return (container, router);
}

Future<void> _save(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Save changes'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Save changes'));
  await tester.pump();
}

void main() {
  testWidgets('readable form retains all populated fields and photo choices',
      (tester) async {
    _size(tester, 1700);
    final client = FakeApiClient();
    await _mount(tester, client, avatarUrl: 'invalid:');
    expect(find.text('Profile photo'), findsOneWidget);
    expect(find.text('Personal information'), findsOneWidget);
    final fields = tester
        .widgetList<TextFormField>(find.byType(TextFormField))
        .toList(growable: false);
    expect(fields, hasLength(4));
    expect(fields[0].controller!.text, 'Amina Catlover');
    expect(fields[1].controller!.text, '+998 90 123 4567');
    expect(fields[2].controller!.text, 'amina_cats');
    expect(fields[3].controller!.text, 'Helping neighborhood cats');
    expect(tester.getSize(find.byType(TextFormField).first).width,
        lessThanOrEqualTo(760));
    expect(find.text('AC'), findsOneWidget);
    await tester.tap(find.text('Change photo'));
    await tester.pumpAndSettle();
    expect(find.text('Choose from gallery'), findsOneWidget);
    expect(find.text('Take photo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('gallery preview uses the selected transparent PNG',
      (tester) async {
    _size(tester, 800);
    final originalPicker = ImagePickerPlatform.instance;
    final picker = _AvatarPicker();
    ImagePickerPlatform.instance = picker;
    addTearDown(() => ImagePickerPlatform.instance = originalPicker);
    await _mount(tester, FakeApiClient());
    await tester.tap(find.text('Change photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose from gallery'));
    await tester.pumpAndSettle();
    expect(picker.sources, [ImageSource.gallery]);
    expect(
        tester
            .widgetList<Image>(find.byType(Image))
            .any((widget) => widget.image is MemoryImage),
        isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Save is disabled until a real change and text restoration is clean',
      (tester) async {
    _size(tester, 800);
    final client = FakeApiClient();
    await _mount(tester, client);

    final save = find.widgetWithText(FilledButton, 'Save changes');
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    final bioField = find.byType(TextFormField).at(3);
    final bio = tester.widget<TextField>(
      find.descendant(of: bioField, matching: find.byType(TextField)),
    );
    expect(bio.decoration!.hintText, isNull);
    expect(find.text('Aydos from Tashkent, cat lover'), findsNothing);

    final name = find.byType(TextFormField).first;
    await tester.enterText(name, 'Amina Updated');
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
    await tester.enterText(name, 'Amina Catlover');
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    expect(client.calls, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('camera choice uses the existing picker path', (tester) async {
    _size(tester, 360);
    final originalPicker = ImagePickerPlatform.instance;
    final picker = _AvatarPicker();
    ImagePickerPlatform.instance = picker;
    addTearDown(() => ImagePickerPlatform.instance = originalPicker);
    await _mount(tester, FakeApiClient());
    await tester.tap(find.text('Change photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Take photo'));
    await tester.pumpAndSettle();
    expect(picker.sources, [ImageSource.camera]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selected avatar uploads before profile details and then returns',
      (tester) async {
    _size(tester, 800);
    final originalPicker = ImagePickerPlatform.instance;
    ImagePickerPlatform.instance = _AvatarPicker();
    addTearDown(() => ImagePickerPlatform.instance = originalPicker);
    final client = FakeApiClient();
    client.setHandler('POST', 'users/me/avatar', (call) {
      final upload = (call.body! as FormData).files.single.value;
      expect(upload.filename, 'avatar.png');
      expect(upload.contentType.toString(), 'image/png');
      return _profile();
    });
    client.setHandler('PATCH', 'users/me', (_) => _profile());
    await _mount(tester, client);
    await tester.tap(find.text('Change photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose from gallery'));
    await tester.pumpAndSettle();
    await _save(tester);
    await tester.pumpAndSettle();
    expect(client.calls.map((call) => call.path).toList(),
        ['users/me/avatar', 'users/me']);
    expect(find.text('Profile home'), findsOneWidget);
  });

  testWidgets('invalid Uzbekistan phone and Telegram values block saving',
      (tester) async {
    _size(tester, 800);
    final client = FakeApiClient();
    await _mount(tester, client);
    await tester.enterText(find.byType(TextFormField).at(1), '12345');
    await tester.enterText(find.byType(TextFormField).at(2), 'bad!');
    await _save(tester);
    await tester.pumpAndSettle();
    expect(find.text('Use Uzbekistan phone format: +998 XX XXX XXXX.'),
        findsOneWidget);
    expect(find.text('Use 5-32 letters, numbers, or underscores.'),
        findsOneWidget);
    expect(client.calls.where((call) => call.method == 'PATCH'), isEmpty);
  });

  testWidgets('valid save normalizes Telegram and phone, then returns',
      (tester) async {
    _size(tester, 800);
    final client = FakeApiClient();
    client.setHandler('PATCH', 'users/me', (_) => _profile());
    await _mount(tester, client);
    await tester.enterText(find.byType(TextFormField).at(0), 'Amina Updated');
    await tester.enterText(find.byType(TextFormField).at(1), '+998901234567');
    await tester.enterText(find.byType(TextFormField).at(2), '@new_amina');
    await tester.enterText(find.byType(TextFormField).at(3), 'New bio');
    await _save(tester);
    await tester.pumpAndSettle();
    final body = client.calls.single.body! as Map<String, Object?>;
    expect(body['name'], 'Amina Updated');
    expect(body['phone_number'], '+998 90 123 4567');
    expect(body['telegram_username'], 'new_amina');
    expect(body['bio'], 'New bio');
    expect(find.text('Profile home'), findsOneWidget);
    expect(find.text('Changes saved.'), findsOneWidget);
  });

  testWidgets('clearing optional phone and Telegram sends empty values',
      (tester) async {
    _size(tester, 800);
    final client = FakeApiClient();
    client.setHandler('PATCH', 'users/me', (_) => _profile());
    await _mount(tester, client);
    await tester.enterText(find.byType(TextFormField).at(1), '');
    await tester.enterText(find.byType(TextFormField).at(2), '');
    await _save(tester);
    await tester.pumpAndSettle();
    final body = client.calls.single.body! as Map<String, Object?>;
    expect(body['phone_number'], '');
    expect(body['telegram_username'], '');
  });

  testWidgets('pending Save prevents duplicate profile requests',
      (tester) async {
    _size(tester, 800);
    final pending = Completer<Object?>();
    final client = FakeApiClient();
    client.setHandler('PATCH', 'users/me', (_) => pending.future);
    await _mount(tester, client);
    await tester.enterText(find.byType(TextFormField).first, 'Amina Pending');
    await _save(tester);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    expect(client.calls.where((call) => call.method == 'PATCH').length, 1);
    pending.complete(_profile());
    await tester.pumpAndSettle();
    expect(find.text('Profile home'), findsOneWidget);
  });

  testWidgets('dirty Cancel asks before leaving', (tester) async {
    _size(tester, 800);
    await _mount(tester, FakeApiClient());
    await tester.enterText(find.byType(TextFormField).first, 'Changed name');
    await tester.ensureVisible(find.text('Cancel'));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Unsaved changes'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.byType(EditProfileScreen), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard changes'));
    await tester.pumpAndSettle();
    expect(find.text('Profile home'), findsOneWidget);
  });

  testWidgets('app bar back protects changes and clean Cancel returns',
      (tester) async {
    _size(tester, 800);
    await _mount(tester, FakeApiClient());
    await tester.enterText(find.byType(TextFormField).first, 'Changed name');
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Unsaved changes'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Amina Catlover');
    await tester.ensureVisible(find.text('Cancel'));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Profile home'), findsOneWidget);
  });

  testWidgets('system back also asks before discarding changes',
      (tester) async {
    _size(tester, 800);
    await _mount(tester, FakeApiClient());
    await tester.enterText(find.byType(TextFormField).first, 'Changed name');
    final pop = tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Unsaved changes'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    await pop;
    expect(find.byType(EditProfileScreen), findsOneWidget);
  });

  testWidgets('system back closes the photo source sheet first',
      (tester) async {
    _size(tester, 800);
    await _mount(tester, FakeApiClient());
    await tester.tap(find.text('Change photo'));
    await tester.pumpAndSettle();
    expect(find.text('Choose from gallery'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Choose from gallery'), findsNothing);
    expect(find.byType(EditProfileScreen), findsOneWidget);
  });

  testWidgets('selected avatar alone triggers the unsaved-changes prompt',
      (tester) async {
    _size(tester, 800);
    final originalPicker = ImagePickerPlatform.instance;
    ImagePickerPlatform.instance = _AvatarPicker();
    addTearDown(() => ImagePickerPlatform.instance = originalPicker);
    await _mount(tester, FakeApiClient());
    await tester.tap(find.text('Change photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose from gallery'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Cancel'));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Unsaved changes'), findsOneWidget);
  });

  testWidgets('compact translated forms stay within the viewport',
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
          profileMeProvider.overrideWith(
              (ref) async => UserProfileData.fromJson(_profile())),
          appLanguageProvider.overrideWith((ref) => language),
        ],
        child: const MaterialApp(home: EditProfileScreen()),
      ));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(TextFormField).first).width,
          lessThanOrEqualTo(760));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('dark theme and larger text keep form controls in bounds',
      (tester) async {
    _size(tester, 360);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        profileMeProvider
            .overrideWith((ref) async => UserProfileData.fromJson(_profile())),
        appLanguageProvider.overrideWith((ref) => AppLanguage.russian),
      ],
      child: MaterialApp(
        theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: const EditProfileScreen(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

class _AvatarPicker extends ImagePickerPlatform {
  final sources = <ImageSource>[];

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    sources.add(source);
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
