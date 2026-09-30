import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';
import 'package:mushukistan_frontend/features/auth/application/auth_controller.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_models.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_repository.dart';
import 'package:mushukistan_frontend/features/profile/presentation/screens/profile_screen.dart';

import '../../support/fakes.dart';

void main() {
  testWidgets('profile shows donation before edit and the support card',
      (tester) async {
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(
            restoreResult: SessionRestoreSuccess(
              AuthSession.restored(
                accessToken: 'token-123',
                user: testUser(),
              ),
            ),
          ),
        ),
        googleIdentityTokenProvider.overrideWithValue(
          FakeGoogleIdentityTokenProvider(),
        ),
        profileMeProvider.overrideWith((ref) async {
          return UserProfileData(
            id: testUser().id,
            email: 'user@example.com',
            registeredAt: DateTime.utc(2026, 7, 1, 10),
            observationCount: 12,
            totalLikesReceived: 45,
            commentCount: 17,
            name: 'Sardor',
          );
        }),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Moderation reports'), findsNothing);
    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(appBar.actions![0], isA<Tooltip>());
    expect((appBar.actions![0] as Tooltip).message, 'Donate to author');
    expect(find.widgetWithText(TextButton, 'Donate to author'), findsOneWidget);
    expect((appBar.actions![1] as IconButton).tooltip, 'Edit profile');

    await tester.tap(find.byTooltip('Donate to author'));
    await tester.pumpAndSettle();

    expect(find.text('Donate to author'), findsNWidgets(2));
    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.text('5614 6810 1028 4564'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Copy card number'), findsOneWidget);
  });

  testWidgets('self profile keeps activity and account entries',
      (tester) async {
    final container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(
        restoreResult: SessionRestoreSuccess(
          AuthSession.restored(accessToken: 'token', user: testUser()),
        ),
      )),
      googleIdentityTokenProvider.overrideWithValue(
        FakeGoogleIdentityTokenProvider(),
      ),
      profileMeProvider.overrideWith((ref) async => UserProfileData(
            id: testUser().id,
            email: 'owner@example.com',
            registeredAt: DateTime.utc(2026, 7, 1),
            observationCount: 12,
            totalLikesReceived: 45,
            commentCount: 17,
            name: 'Sardor',
            bio: 'Helping neighborhood cats',
            phoneNumber: '+998901234567',
            telegramUsername: 'sardor_cat',
            isModerator: true,
          )),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: ProfileScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Sardor'), findsOneWidget);
    expect(find.text('Helping neighborhood cats'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('45'), findsOneWidget);
    expect(find.text('17'), findsOneWidget);
    expect(find.text('My lost pets'), findsOneWidget);
    expect(find.text('My rehoming posts'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Moderation reports'), findsNWidgets(2));
  });

  testWidgets('compact self profile keeps app bar and stats in bounds',
      (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(
        restoreResult: SessionRestoreSuccess(
          AuthSession.restored(accessToken: 'token', user: testUser()),
        ),
      )),
      googleIdentityTokenProvider.overrideWithValue(
        FakeGoogleIdentityTokenProvider(),
      ),
      profileMeProvider.overrideWith((ref) async => UserProfileData(
            id: testUser().id,
            email: 'owner@example.com',
            registeredAt: DateTime.utc(2026, 7, 1),
            observationCount: 12,
            totalLikesReceived: 45,
            commentCount: 17,
            name: 'A very long contributor name for compact screens',
          )),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: ProfileScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Donate to author'), findsOneWidget);
    expect(find.byTooltip('Edit profile'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
