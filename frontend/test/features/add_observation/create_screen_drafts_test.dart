import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as image;
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:mushukistan_frontend/core/localization/app_strings.dart';
import 'package:mushukistan_frontend/core/localization/language_controller.dart';
import 'package:mushukistan_frontend/core/network/api_error.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';
import 'package:mushukistan_frontend/features/add_observation/application/add_observation_controller.dart';
import 'package:mushukistan_frontend/features/add_observation/application/pet_post_draft_controller.dart';
import 'package:mushukistan_frontend/features/add_observation/presentation/screens/add_observation_screen.dart';
import 'package:mushukistan_frontend/features/adoption_posts/presentation/screens/adoption_post_create_screen.dart';
import 'package:mushukistan_frontend/features/lost_pets/presentation/screens/lost_pet_create_screen.dart';

import '../../support/fakes.dart';

class _PhotoPicker extends ImagePickerPlatform {
  @override
  Future<List<XFile>> getMultiImageWithOptions(
          {MultiImagePickerOptions options =
              const MultiImagePickerOptions()}) async =>
      [
        XFile.fromData(image.encodeJpg(image.Image(width: 8, height: 8)),
            name: 'draft.jpg', mimeType: 'image/jpeg')
      ];
}

/// Per-type facts the tests need: route, card label, endpoint, response.
class _Type {
  const _Type(this.type, this.path, this.endpoint, this.label, this.message,
      this.response);
  final PetPostType type;
  final String path;
  final String endpoint;
  final String label;
  final String message;
  final Map<String, Object?> response;
  bool get lost => type == PetPostType.lostPet;
}

final _english = AppStrings.forLanguage(AppLanguage.english);

final _types = [
  _Type(PetPostType.lostPet, '/add/lost-pet', 'lost-pets',
      _english.lostPetDraftLabel, _english.deleteLostPetDraftMessage, {
    'item_type': 'lost_pet',
    'id': 'lost-1',
    'pet_name': 'Milo',
    'owner_phone_number': '+998901234567',
    'photo_url': 'invalid:',
    'photo_urls': ['invalid:'],
    'last_seen_location': {'latitude': 41.3, 'longitude': 69.25},
    'additional_info': 'Grey tabby, blue collar',
    'is_resolved': false,
    'comment_count': 0,
    'created_at': '2026-11-24T10:00:00Z',
  }),
  _Type(PetPostType.adoption, '/add/adoption', 'adoption-posts',
      _english.rehomingDraftLabel, _english.deleteRehomingDraftMessage, {
    'item_type': 'adoption',
    'id': 'adopt-1',
    'pet_name': 'Milo',
    'owner_phone_number': '+998901234567',
    'photo_url': 'invalid:',
    'photo_urls': ['invalid:'],
    'additional_info': 'Grey tabby, blue collar',
    'is_resolved': false,
    'comment_count': 0,
    'created_at': '2026-11-24T10:00:00Z',
  }),
];

FakeApiClient _client() => FakeApiClient()
  ..setHandler(
      'GET',
      'users/me',
      (_) => {
            'id': 'owner-one',
            'email': 'owner@example.com',
            'name': 'Owner',
            'phone_number': '+998 90 123 4567',
            'registered_at': '2026-01-01T00:00:00Z',
            'observation_count': 0,
            'total_likes_received': 0,
            'comment_count': 0,
          });

Future<(ProviderContainer, GoRouter)> _mount(
    WidgetTester tester, FakeApiClient client) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final originalPicker = ImagePickerPlatform.instance;
  ImagePickerPlatform.instance = _PhotoPicker();
  addTearDown(() => ImagePickerPlatform.instance = originalPicker);
  final container = ProviderContainer(overrides: [
    mushukistanApiProvider.overrideWithValue(MushukistanApi(client: client)),
    appLanguageProvider.overrideWith((ref) => AppLanguage.english),
  ]);
  addTearDown(container.dispose);
  final router = GoRouter(initialLocation: '/add', routes: [
    GoRoute(
      path: '/feed',
      builder: (_, __) => const Scaffold(body: Text('Feed destination')),
    ),
    GoRoute(
      path: '/add',
      builder: (_, __) => const AddObservationScreen(),
      routes: [
        GoRoute(
            path: 'lost-pet', builder: (_, __) => const LostPetCreateScreen()),
        GoRoute(
            path: 'adoption',
            builder: (_, __) => const AdoptionPostCreateScreen()),
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

/// Photo thumbnails (the Lost Pet map draws its own tile images).
final _thumbnails = find.byWidgetPredicate(
    (widget) => widget is Image && widget.image is MemoryImage);

Finder _field(String label) => find.widgetWithText(TextFormField, label);

/// Adds a photo, pet name, additional info and (Lost Pet) a location.
Future<void> _fill(WidgetTester tester, _Type t) async {
  await tester.tap(find.byIcon(Icons.add_photo_alternate_outlined));
  await tester.pumpAndSettle();
  await tester.enterText(
      _field(t.lost ? _english.petsName : _english.petName), 'Milo');
  await tester.enterText(
      _field(_english.additionalInformation), 'Grey tabby, blue collar');
  if (t.lost) {
    tester
        .widget<LostPetLocationPicker>(find.byType(LostPetLocationPicker))
        .onSelected(const GeoPoint(latitude: 41.3, longitude: 69.25));
  }
  await tester.pumpAndSettle();
}

void main() {
  for (final t in _types) {
    final provider = petPostDraftProvider(t.type);

    testWidgets('${t.path}: opening and leaving without input leaves no draft',
        (tester) async {
      final (container, router) = await _mount(tester, _client());
      router.go(t.path);
      await tester.pumpAndSettle();
      router.go('/add');
      await tester.pumpAndSettle();
      expect(container.read(provider).hasDraft, isFalse);
      expect(find.text('Continue draft'), findsNothing);
    });

    testWidgets('${t.path}: entered data survives leaving and is restored',
        (tester) async {
      final (container, router) = await _mount(tester, _client());
      router.go(t.path);
      await tester.pumpAndSettle();
      await _fill(tester, t);
      final id = container.read(provider).publicationId;
      router.go('/add');
      await tester.pumpAndSettle();

      expect(find.text('Continue draft'), findsOneWidget);
      expect(find.text(t.label), findsOneWidget);
      // The Cat post draft is untouched by this type's draft.
      expect(
          container.read(addObservationControllerProvider).hasDraft, isFalse);

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      final draft = container.read(provider);
      expect(draft.publicationId, id);
      expect(draft.photos, hasLength(1));
      expect(find.text('Milo'), findsOneWidget);
      expect(find.text('Grey tabby, blue collar'), findsOneWidget);
      expect(_thumbnails, findsOneWidget);
      if (t.lost) {
        expect(draft.location?.longitude, 69.25);
        expect(find.text(_english.lastSeenLocationSelected), findsOneWidget);
      }
    });

    testWidgets('${t.path}: deleting the draft leaves an empty form',
        (tester) async {
      final (container, router) = await _mount(tester, _client());
      router.go(t.path);
      await tester.pumpAndSettle();
      await _fill(tester, t);
      final id = container.read(provider).publicationId;
      router.go('/add');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete draft'));
      await tester.pumpAndSettle();
      expect(find.text('Delete draft?'), findsOneWidget);
      expect(find.text(t.message), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Draft deleted.'), findsOneWidget);
      expect(find.text('Continue draft'), findsNothing);
      expect(container.read(provider).hasDraft, isFalse);
      expect(container.read(provider).publicationId, isNot(id));

      router.go(t.path);
      await tester.pumpAndSettle();
      expect(find.text('Milo'), findsNothing);
      expect(find.text('Grey tabby, blue collar'), findsNothing);
      expect(_thumbnails, findsNothing);
      expect(container.read(provider).photos, isEmpty);
    });

    testWidgets('${t.path}: publishing clears the draft', (tester) async {
      final client = _client()
        ..setHandler('POST', t.endpoint, (_) => t.response);
      final (container, router) = await _mount(tester, client);
      router.go(t.path);
      await tester.pumpAndSettle();
      await _fill(tester, t);
      final id = container.read(provider).publicationId;
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      final publish = find.widgetWithText(FilledButton,
          t.lost ? _english.publishLostPet : _english.publishAdoptionPost);
      await tester.ensureVisible(publish);
      await tester.tap(publish);
      await tester.pumpAndSettle();

      expect(find.text('Feed destination'), findsOneWidget);
      expect(client.calls.where((c) => c.method == 'POST'), hasLength(1));
      final draft = container.read(provider);
      expect(draft.hasDraft, isFalse);
      expect(draft.publicationId, isNot(id));
      router.go('/add');
      await tester.pumpAndSettle();
      expect(find.text('Continue draft'), findsNothing);
    });

    test('${t.path}: outcome unknown keeps the draft and its publicationId',
        () async {
      final client = _client()
        ..setHandler(
            'POST',
            t.endpoint,
            (_) => throw const MushukistanApiException(
                kind: ApiFailureKind.network,
                code: 'NETWORK',
                message: 'offline'));
      final controller =
          PetPostDraftController(MushukistanApi(client: client), t.type)
            ..addPhotos([
              LostPetPhotoUpload(
                  bytes: image.encodeJpg(image.Image(width: 8, height: 8)),
                  filename: 'draft.jpg',
                  contentType: 'image/jpeg')
            ])
            ..setPetName('Milo')
            ..setLocation(const GeoPoint(latitude: 41.3, longitude: 69.25));
      final id = controller.state.publicationId;
      final published =
          await controller.submit(strings: _english, contactConsent: true);
      expect(published, isFalse);
      expect(controller.state.outcomeUnknown, isTrue);
      expect(controller.state.locked, isTrue);
      expect(controller.state.publicationId, id);
      expect(controller.state.hasDraft, isTrue);
      expect(controller.state.errorMessage, isNotNull);
    });
  }

  test('defaults alone are not a draft; user content is', () {
    expect(PetPostDraftState().hasDraft, isFalse);
    expect(PetPostDraftState(petName: '  ').hasDraft, isFalse);
    expect(PetPostDraftState(petName: 'Milo').hasDraft, isTrue);
    expect(PetPostDraftState(additionalInfo: 'Shy').hasDraft, isTrue);
    expect(
        PetPostDraftState(
                location: const GeoPoint(latitude: 41.3, longitude: 69.25))
            .hasDraft,
        isTrue);
  });

  testWidgets('each type keeps its own draft and Create lists all of them',
      (tester) async {
    final (container, router) = await _mount(tester, _client());
    container
        .read(addObservationControllerProvider.notifier)
        .setDescription('Cat draft');
    container.read(lostPetDraftProvider.notifier).setPetName('Lost Milo');
    container
        .read(adoptionPostDraftProvider.notifier)
        .setPetName('Rehome Luna');
    router.go('/add');
    await tester.pumpAndSettle();
    expect(find.text('Continue draft'), findsOneWidget);
    expect(find.text('Draft status'), findsOneWidget);
    expect(find.text(_english.lostPetDraftLabel), findsOneWidget);
    expect(find.text(_english.rehomingDraftLabel), findsOneWidget);
    expect(find.text('Delete draft'), findsNWidgets(3));
    expect(container.read(lostPetDraftProvider).petName, 'Lost Milo');
    expect(container.read(adoptionPostDraftProvider).petName, 'Rehome Luna');
    expect(container.read(addObservationControllerProvider).description,
        'Cat draft');
  });
}
