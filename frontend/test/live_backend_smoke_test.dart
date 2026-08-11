import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/core/config/app_environment.dart';
import 'package:mushukistan_frontend/core/network/api_client.dart';
import 'package:mushukistan_frontend/core/network/api_error.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_models.dart';
import 'package:mushukistan_frontend/features/auth/infrastructure/auth_repository_impl.dart';

import 'support/fakes.dart';

void main() {
  test(
    'live backend accepts register and login through the frontend repository',
    () async {
      final environment = AppEnvironment.fromBuildEnvironment();
      final tokenStore = FakeAuthTokenStore();
      final apiClient = DioMushukistanApiClient.fromEnvironment(
        environment: environment,
        tokenStore: tokenStore,
      );
      final repository = MushukistanAuthRepository(
        apiClient: apiClient,
        tokenStore: tokenStore,
      );

      final suffix = DateTime.now().microsecondsSinceEpoch;
      final email = 'codex-$suffix@example.com';
      const password = 'password1';
      const name = 'Codex';

      final registration = await repository.register(
        RegisterCredentials(
          email: email,
          password: password,
          preferredLanguage: 'en',
          acceptTerms: true,
          acceptPrivacy: true,
          name: name,
        ),
      );

      expect(registration.email, email);
      expect(registration.devVerificationToken, isNotEmpty);

      await repository.verifyEmail(registration.devVerificationToken!);

      final session = await repository.login(
        AuthCredentials(email: email, password: password),
      );

      expect(session.user.email, email);
      expect(session.accessToken, isNotEmpty);
      expect(await tokenStore.read(), session.accessToken);
    },
    skip: const String.fromEnvironment('RUN_LIVE_BACKEND_TESTS').trim() != '1',
  );

  test(
    'live backend returns a normalized auth error envelope',
    () async {
      final environment = AppEnvironment.fromBuildEnvironment();
      final apiClient = DioMushukistanApiClient.fromEnvironment(
        environment: environment,
        tokenStore: FakeAuthTokenStore(),
      );

      await expectLater(
        () => apiClient.postJson<Map<String, Object?>>(
          'auth/login',
          authenticated: false,
          body: <String, Object?>{
            'email': 'nobody@example.com',
            'password': 'invalidpassword',
          },
          decoder: (json) => Map<String, Object?>.from(json! as Map),
        ),
        throwsA(isA<MushukistanApiException>().having(
          (error) => error.kind,
          'kind',
          ApiFailureKind.unauthorized,
        )),
      );
    },
    skip: const String.fromEnvironment('RUN_LIVE_BACKEND_TESTS').trim() != '1',
  );

  test(
    'live backend supports the MVP observation flow',
    () async {
      final environment = AppEnvironment.fromBuildEnvironment();
      final tokenStore = FakeAuthTokenStore();
      final apiClient = DioMushukistanApiClient.fromEnvironment(
        environment: environment,
        tokenStore: tokenStore,
      );
      final api = MushukistanApi(client: apiClient);
      final repository = MushukistanAuthRepository(
        apiClient: apiClient,
        tokenStore: tokenStore,
      );

      final suffix = DateTime.now().microsecondsSinceEpoch;
      final email = 'codex-flow-$suffix@example.com';
      const password = 'password1';

      final registration = await repository.register(
        RegisterCredentials(
          email: email,
          password: password,
          preferredLanguage: 'en',
          acceptTerms: true,
          acceptPrivacy: true,
          name: 'Codex',
        ),
      );
      await repository.verifyEmail(registration.devVerificationToken!);
      await repository.login(
        AuthCredentials(email: email, password: password),
      );

      final cats = await api.listCats(
        filter: 'nearby',
        lat: 41.2995,
        lon: 69.2401,
        radiusMeters: 4000,
        limit: 20,
      );
      expect(cats.limit, 20);

      final photoBytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jPZ0AAAAASUVORK5CYII=',
      );
      final existingCatId = cats.items.isNotEmpty ? cats.items.first.id : null;
      final post = await api.createObservation(
        photos: [
          ObservationPhotoUpload(
            bytes: photoBytes,
            filename: 'observation.png',
            contentType: 'image/png',
          ),
        ],
        location: const GeoPoint(latitude: 41.2995, longitude: 69.2401),
        description: 'Codex live smoke test',
        existingCatId: existingCatId,
        newCatName: existingCatId == null ? 'Codex smoke cat' : null,
        newCatStatus: existingCatId == null ? 'healthy' : null,
        newCatLocation: existingCatId == null
            ? const GeoPoint(latitude: 41.2995, longitude: 69.2401)
            : null,
      );

      expect(post.id, isNotEmpty);
      expect(post.description, 'Codex live smoke test');

      final likeResult = await api.likePost(post.id);
      expect(likeResult.liked, isTrue);
      expect(likeResult.likeCount, greaterThanOrEqualTo(1));

      await api.unlikePost(post.id);

      final feed = await api.listFeed(
        filter: 'recent',
        lat: 41.2995,
        lon: 69.2401,
        radiusMeters: 4000,
        limit: 20,
      );
      expect(feed.items.map((item) => item.id), contains(post.id));

      final leaderboard = await api.listLeaderboard(
        'most_active',
        period: 'week',
        limit: 10,
      );
      expect(leaderboard, isNotNull);
    },
    skip: const String.fromEnvironment('RUN_LIVE_BACKEND_TESTS').trim() != '1',
  );
}
