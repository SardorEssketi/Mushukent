import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/core/network/api_client.dart';
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
}
