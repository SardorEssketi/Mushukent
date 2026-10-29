import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';
import 'package:mushukistan_frontend/core/onboarding/authenticated_onboarding_flow.dart';
import 'package:mushukistan_frontend/core/onboarding/authenticated_onboarding_store.dart';
import 'package:mushukistan_frontend/features/auth/application/auth_controller.dart';

import '../../support/fakes.dart';

void main() {
  testWidgets('first sign-in asks for the language only, without a welcome',
      (tester) async {
    final user = testUser();
    final store = InMemoryAuthenticatedOnboardingStore();
    final client = FakeApiClient()
      ..setHandler('PATCH', 'users/me', (_) => null);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserProvider.overrideWithValue(user),
        authenticatedOnboardingStoreProvider.overrideWithValue(store),
        mushukistanApiProvider
            .overrideWithValue(MushukistanApi(client: client)),
      ],
      child: const MaterialApp(
        home: AuthenticatedOnboardingFlow(child: Scaffold(body: Text('Feed'))),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Choose your language'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);
    expect(find.textContaining('Welcome to Mushukistan'), findsNothing);
    expect(find.text('Feed'), findsOneWidget);
    expect(await store.hasSeen(user.id), isTrue);
  });
}
