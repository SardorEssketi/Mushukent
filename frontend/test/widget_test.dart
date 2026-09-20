// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mushukistan_frontend/app.dart';
import 'package:mushukistan_frontend/features/auth/application/auth_controller.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_repository.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('app boots', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository(
              restoreResult: const SessionRestoreMissing(),
            ),
          ),
          googleIdentityTokenProvider.overrideWithValue(
            FakeGoogleIdentityTokenProvider(),
          ),
        ],
        child: const MushukistanApp(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(ProviderScope), findsOneWidget);
    expect(find.byType(Scaffold), findsWidgets);
  });
}
