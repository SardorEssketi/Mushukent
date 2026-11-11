import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/core/localization/language_controller.dart';
import 'package:mushukistan_frontend/core/network/api_client.dart';
import 'package:mushukistan_frontend/core/network/api_error.dart';
import 'package:mushukistan_frontend/features/auth/application/auth_controller.dart';
import 'package:mushukistan_frontend/features/profile/presentation/screens/account_security_screen.dart';

import '../../support/fakes.dart';

void main() {
  testWidgets(
      'Google-only account has email and logout without password management',
      (tester) async {
    final client = FakeApiClient();
    client.setHandler('GET', 'auth/methods',
        (_) => {'has_password': false, 'email_verified': true});
    await tester.pumpWidget(ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(client),
        currentUserProvider
            .overrideWithValue(testUser(email: 'google-only@example.com')),
      ],
      child: const MaterialApp(home: AccountSecurityScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('google-only@example.com'), findsOneWidget);
    expect(find.text('Verified'), findsOneWidget);
    expect(find.text('Password'), findsNothing);
    expect(find.text('Add password (optional)'), findsNothing);
    expect(find.text('Google'), findsNothing);
    expect(find.text('Logout'), findsOneWidget);
  });

  testWidgets('password account shows email security and change form',
      (tester) async {
    final client = FakeApiClient();
    client.setHandler(
      'GET',
      'auth/methods',
      (_) => {'has_password': true, 'email_verified': false},
    );
    client.setHandler('POST', 'auth/change-password', (_) => null);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(client),
        currentUserProvider.overrideWithValue(
          testUser(email: 'password-user@example.com'),
        ),
      ],
      child: const MaterialApp(home: AccountSecurityScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('password-user@example.com'), findsOneWidget);
    expect(find.text('Needs verification'), findsOneWidget);
    expect(find.text('Enabled'), findsOneWidget);
    expect(find.text('Google'), findsNothing);
    await tester.ensureVisible(find.text('Change password'));
    await tester.tap(find.text('Change password'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    expect(fields, findsNWidgets(3));
    await tester.enterText(fields.at(0), 'Password123');
    await tester.enterText(fields.at(1), 'Password456');
    await tester.enterText(fields.at(2), 'Mismatch123');
    await tester.ensureVisible(find.text('Save password'));
    await tester.tap(find.text('Save password'));
    await tester.pumpAndSettle();
    expect(find.text('Passwords do not match.'), findsOneWidget);
    expect(client.calls.where((call) => call.path == 'auth/change-password'),
        isEmpty);

    await tester.enterText(fields.at(2), 'Password456');
    await tester.ensureVisible(find.text('Save password'));
    await tester.tap(find.text('Save password'));
    await tester.pumpAndSettle();
    expect(client.calls.where((call) => call.path == 'auth/change-password'),
        hasLength(1));
  });

  testWidgets('wrong current password is reported without mentioning email',
      (tester) async {
    tester.view.physicalSize = const Size(600, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = FakeApiClient();
    client.setHandler('GET', 'auth/methods',
        (_) => {'has_password': true, 'email_verified': true});
    client.setHandler(
      'POST',
      'auth/change-password',
      (_) => throw const MushukistanApiException(
        kind: ApiFailureKind.unauthorized,
        statusCode: 401,
        code: 'INVALID_CREDENTIALS',
        message: 'Invalid current password.',
      ),
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(client),
        appLanguageProvider.overrideWith((ref) => AppLanguage.russian),
        currentUserProvider
            .overrideWithValue(testUser(email: 'password-user@example.com')),
      ],
      child: const MaterialApp(home: AccountSecurityScreen()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Изменить пароль'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'WrongPass1');
    await tester.enterText(fields.at(1), 'Password456');
    await tester.enterText(fields.at(2), 'Password456');
    await tester.tap(find.text('Сохранить пароль'));
    await tester.pumpAndSettle();
    expect(find.text('Текущий пароль указан неверно.'), findsOneWidget);
    expect(find.textContaining('Email'), findsNothing);
  });

  testWidgets('schema validation errors (list details) show the length hint',
      (tester) async {
    tester.view.physicalSize = const Size(600, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = FakeApiClient();
    client.setHandler('GET', 'auth/methods',
        (_) => {'has_password': true, 'email_verified': true});
    client.setHandler(
      'POST',
      'auth/change-password',
      (_) => throw const MushukistanApiException(
        kind: ApiFailureKind.validation,
        statusCode: 422,
        code: 'VALIDATION_ERROR',
        message: 'Validation failed.',
        details: [
          {
            'loc': ['body', 'new_password'],
            'type': 'string_too_long',
          }
        ],
      ),
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(client),
        currentUserProvider
            .overrideWithValue(testUser(email: 'password-user@example.com')),
      ],
      child: const MaterialApp(home: AccountSecurityScreen()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change password'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Current123');
    await tester.enterText(fields.at(1), 'Password456');
    await tester.enterText(fields.at(2), 'Password456');
    await tester.tap(find.text('Save password'));
    await tester.pumpAndSettle();
    expect(find.text('Use 8 to 128 characters.'), findsWidgets);
    expect(find.text('Could not save the password. Try again.'), findsNothing);
  });
}
