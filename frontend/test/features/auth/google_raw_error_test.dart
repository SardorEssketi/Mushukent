// EMU-107 reproduction with the pre-existing API only: the plugin's raw text
// ("[16] Cancelled by user.") must never reach the Login screen.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mushukistan_frontend/features/auth/application/auth_controller.dart';
import 'package:mushukistan_frontend/features/auth/infrastructure/google_sign_in_service.dart';
import 'package:mushukistan_frontend/features/auth/presentation/screens/login_screen.dart';

import '../../support/fakes.dart';

void main() {
  testWidgets('raw Google SDK text is not shown on Login', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      googleIdentityTokenProvider.overrideWithValue(
        FakeGoogleIdentityTokenProvider(
          error: const GoogleSignInFlowException('[16] Cancelled by user.'),
        ),
      ),
    ]);
    addTearDown(container.dispose);
    final router = GoRouter(initialLocation: '/login', routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    expect(find.textContaining('[16]'), findsNothing);
    expect(find.textContaining('Cancelled by user'), findsNothing);
  });
}
