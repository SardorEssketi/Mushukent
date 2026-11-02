import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:mushukistan_frontend/core/localization/app_strings.dart';
import 'package:mushukistan_frontend/core/localization/language_controller.dart';
import 'package:mushukistan_frontend/core/network/api_client.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';
import 'package:mushukistan_frontend/core/storage/token_store.dart';
import 'package:mushukistan_frontend/core/storage/token_store_provider.dart';
import 'package:mushukistan_frontend/features/add_observation/application/add_observation_controller.dart';
import 'package:mushukistan_frontend/features/add_observation/presentation/screens/add_observation_details_screen.dart';
import 'package:mushukistan_frontend/features/adoption_posts/presentation/screens/adoption_post_create_screen.dart';
import 'package:mushukistan_frontend/features/lost_pets/presentation/screens/lost_pet_create_screen.dart';

import '../../core/network/publication_completed_recovery_test.dart';

class ValidationServer extends RemovedPublicationServer {
  ValidationServer(String kind) : super(kind, 404);
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
      Future<void>? cancelFuture) async {
    if (options.method != 'POST') {
      return super.fetch(options, stream, cancelFuture);
    }
    if (stream != null) await stream.drain<void>();
    requests.add(options);
    posts.add(options.headers['Idempotency-Key'] as String);
    return reply(422, {
      'success': false,
      'error': {'code': 'INVALID_PAYLOAD', 'message': 'Correct the draft.'}
    });
  }
}

class PhotoPicker extends ImagePickerPlatform {
  @override
  Future<List<XFile>> getMultiImageWithOptions(
          {MultiImagePickerOptions options =
              const MultiImagePickerOptions()}) async =>
      [
        XFile.fromData(image.encodeJpg(image.Image(width: 8, height: 8)),
            name: 'synthetic.jpg', mimeType: 'image/jpeg')
      ];
}

void main() {
  for (final type in ['observation', 'needs_help', 'lost_pet', 'adoption']) {
    for (final validation in [false, true]) {
      testWidgets(
          '$type: ${validation ? "validation allows correction" : "completed unavailable locks creation"}',
          (tester) async {
        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final originalPicker = ImagePickerPlatform.instance;
        ImagePickerPlatform.instance = PhotoPicker();
        addTearDown(() => ImagePickerPlatform.instance = originalPicker);
        final regular = type == 'observation' || type == 'needs_help';
        final kind = regular
            ? 'post'
            : type == 'lost_pet'
                ? 'lost_pet'
                : 'adoption_post';
        final server = validation
            ? ValidationServer(kind)
            : RemovedPublicationServer(kind, 404);
        final store = GuardedAuthTokenStore(InMemoryAuthTokenStore());
        await store.write('header.eyJzdWIiOiJBIn0.signature');
        final dio = Dio(BaseOptions(
            baseUrl: 'https://example.test/api/v1/',
            validateStatus: (_) => true))
          ..httpClientAdapter = server;
        final api = MushukistanApi(
            client: DioMushukistanApiClient(dio: dio, tokenStore: store));
        final container = ProviderContainer(overrides: [
          mushukistanApiProvider.overrideWithValue(api),
          tokenStoreProvider.overrideWithValue(store),
          appLanguageProvider.overrideWith((ref) => AppLanguage.english),
        ]);
        addTearDown(container.dispose);
        final controller =
            container.read(addObservationControllerProvider.notifier);
        if (regular) {
          controller.setPhoto(
              bytes: image.encodeJpg(image.Image(width: 8, height: 8)),
              filename: 'synthetic.jpg',
              contentType: 'image/jpeg');
          controller.setKind(type);
          controller
              .setLocation(const GeoPoint(latitude: 41.3, longitude: 69.25));
          controller.setDescription('Synthetic draft');
        }
        await tester.pumpWidget(UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
                home: regular
                    ? const AddObservationDetailsScreen()
                    : type == 'lost_pet'
                        ? const LostPetCreateScreen()
                        : const AdoptionPostCreateScreen())));
        await tester.pumpAndSettle();
        if (!regular) {
          await tester.tap(find.byType(OutlinedButton).first);
          await tester.pumpAndSettle();
          await tester.enterText(
              find.byType(TextFormField).first, 'Synthetic pet');
          if (type == 'lost_pet') {
            tester
                .widget<LostPetLocationPicker>(
                    find.byType(LostPetLocationPicker))
                .onSelected(const GeoPoint(latitude: 41.3, longitude: 69.25));
          }
          await tester.tap(find.byType(CheckboxListTile));
          await tester.pumpAndSettle();
        }
        final strings = AppStrings.forLanguage(AppLanguage.english);
        final publish = regular
            ? type == 'needs_help'
                ? strings.publishNeedsHelp
                : strings.publishObservation
            : type == 'lost_pet'
                ? strings.publishLostPet
                : strings.publishAdoptionPost;
        final button = find.widgetWithText(FilledButton, publish);
        await tester.ensureVisible(button);
        final originalAction = tester.widget<FilledButton>(button).onPressed!;
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(server.posts, hasLength(1));
        final operationId = server.posts.single;
        if (validation) {
          expect(
              tester
                  .widget<TextFormField>(find.byType(TextFormField).first)
                  .enabled,
              isTrue);
          await tester.enterText(
              find.byType(TextFormField).first, 'Corrected draft');
          await tester
              .ensureVisible(find.widgetWithText(FilledButton, publish));
          await tester.tap(find.widgetWithText(FilledButton, publish));
          await tester.pumpAndSettle();
          expect(server.posts, hasLength(2));
          expect(server.posts.last, isNot(operationId));
        } else {
          final recover =
              find.widgetWithText(FilledButton, strings.checkPublicationStatus);
          await tester.ensureVisible(recover);
          await tester.tap(recover);
          await tester.pumpAndSettle();
          final terminal = find.widgetWithText(
              FilledButton, strings.publicationAlreadyPublished);
          expect(tester.widget<FilledButton>(terminal).onPressed, isNull);
          expect(find.text(strings.publicationCompletedUnavailable),
              findsOneWidget);
          expect(find.textContaining('SYNTHETIC_RESTRICTED'), findsNothing);
          for (final field in find.byType(TextFormField).evaluate()) {
            expect((field.widget as TextFormField).enabled, isFalse);
          }
          // Even a queued callback from before terminal rendering cannot submit.
          originalAction();
          originalAction();
          await tester.pumpAndSettle();
          expect(server.posts, [operationId]);
          if (regular) {
            expect(controller.state.publicationId, operationId);
            expect(controller.state.completedUnavailable, isTrue);
          }
          // Account transition removes the prior account's terminal draft/result.
          await store.write('header.eyJzdWIiOiJCIn0.signature');
          await tester.pumpAndSettle();
          expect(
              find.text(strings.publicationCompletedUnavailable), findsNothing);
          expect(find.text(strings.publicationAlreadyPublished), findsNothing);
          expect(server.posts, [operationId]);
        }
      });
    }
  }
}
