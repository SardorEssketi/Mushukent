import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/core/network/api_client.dart';
import 'package:mushukistan_frontend/features/auth/application/auth_controller.dart';
import 'package:mushukistan_frontend/features/profile/presentation/screens/account_security_screen.dart';

import '../../support/fakes.dart';

void main() {
  testWidgets('Google-only account sets a password with one submission',
      (tester) async {
    final client = FakeApiClient();
    var hasPassword = false;
    final save = Completer<Object?>();
    client.setHandler(
        'GET',
        'auth/methods',
        (_) => {
              'has_password': hasPassword,
              'google_connected': true,
            });
    client.setHandler('POST', 'auth/set-password', (_) async {
      await save.future;
      hasPassword = true;
      return null;
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(client)],
      child: const MaterialApp(home: AccountSecurityScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Connected'), findsOneWidget);
    expect(find.text('Not set'), findsOneWidget);
    await tester.tap(find.text('Set password'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Password123');
    await tester.enterText(fields.at(1), 'Password123');
    await tester.tap(find.text('Save password'));
    await tester.pump();
    expect(
        client.calls.where((call) => call.path == 'auth/set-password').length,
        1);
    save.complete(null);
    await tester.pumpAndSettle();
    expect(find.text('Password saved.'), findsOneWidget);
    expect(find.text('Set'), findsOneWidget);
  });

  testWidgets('Password account shows change form and validates confirmation',
      (tester) async {
    final client = FakeApiClient();
    client.setHandler(
        'GET',
        'auth/methods',
        (_) => {
              'has_password': true,
              'google_connected': false,
            });
    client.setHandler('POST', 'auth/change-password', (_) => null);
    await tester.pumpWidget(ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(client)],
      child: const MaterialApp(home: AccountSecurityScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Not connected'), findsOneWidget);
    await tester.tap(find.text('Change password'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    expect(fields, findsNWidgets(3));
    await tester.enterText(fields.at(0), 'Password123');
    await tester.enterText(fields.at(1), 'Password456');
    await tester.enterText(fields.at(2), 'Mismatch123');
    await tester.ensureVisible(find.text('Save password'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save password'));
    await tester.pumpAndSettle();
    expect(find.text('Passwords do not match.'), findsOneWidget);
    expect(client.calls.where((call) => call.path == 'auth/change-password'),
        isEmpty);
    await tester.enterText(fields.at(2), 'Password456');
    await tester.ensureVisible(find.text('Save password'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save password'));
    await tester.pumpAndSettle();
    expect(
        client.calls
            .where((call) => call.path == 'auth/change-password')
            .length,
        1);
  });

  testWidgets('Password account connects Google without duplicate submissions',
      (tester) async {
    final client = FakeApiClient();
    final google = FakeGoogleIdentityTokenProvider();
    final connection = Completer<Object?>();
    var connected = false;
    client.setHandler('GET', 'auth/methods',
        (_) => {'has_password': true, 'google_connected': connected});
    client.setHandler('POST', 'auth/connect-google', (_) async {
      await connection.future;
      connected = true;
      return null;
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(client),
        googleIdentityTokenProvider.overrideWithValue(google),
      ],
      child: const MaterialApp(home: AccountSecurityScreen()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Connect Google'));
    await tester.pump();
    expect(google.calls, 1);
    expect(
        client.calls.where((call) => call.path == 'auth/connect-google').length,
        1);
    connection.complete(null);
    await tester.pumpAndSettle();
    expect(find.text('Connected'), findsOneWidget);
    expect(find.text('Set'), findsOneWidget);
    expect(find.text('Google connected.'), findsOneWidget);
  });

  testWidgets('Google connection failure hides SDK exception details',
      (tester) async {
    final client = FakeApiClient();
    client.setHandler('GET', 'auth/methods',
        (_) => {'has_password': true, 'google_connected': false});
    final google = FakeGoogleIdentityTokenProvider(
        error: StateError('sensitive SDK exception detail'));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(client),
        googleIdentityTokenProvider.overrideWithValue(google),
      ],
      child: const MaterialApp(home: AccountSecurityScreen()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Connect Google'));
    await tester.pumpAndSettle();
    expect(find.text('Could not connect Google. Please try again.'),
        findsOneWidget);
    expect(find.textContaining('sensitive SDK exception'), findsNothing);
  });
}
