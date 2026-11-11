// Accessible names of icon-only controls (AUTH-201, AUTH-202, AUTH-203,
// AUTH-217). The tooltip of an IconButton is its accessible name on Android;
// these tests read it from the semantics tree, which is what assistive
// technology receives.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as image;
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:mushukistan_frontend/core/localization/language_controller.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';
import 'package:mushukistan_frontend/features/adoption_posts/presentation/screens/adoption_post_create_screen.dart';
import 'package:mushukistan_frontend/features/auth/application/auth_controller.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_models.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_repository.dart';
import 'package:mushukistan_frontend/features/auth/presentation/screens/login_screen.dart';
import 'package:mushukistan_frontend/features/auth/presentation/screens/register_screen.dart';
import 'package:mushukistan_frontend/features/lost_pets/presentation/screens/lost_pet_create_screen.dart';
import 'package:mushukistan_frontend/features/notifications/data/notification_api.dart';
import 'package:mushukistan_frontend/features/notifications/presentation/notification_center_screen.dart';
import 'package:mushukistan_frontend/features/profile/presentation/screens/profile_screen.dart';

import '../../support/fakes.dart';

/// Semantics of the button that shows [tooltip] (its accessible name).
SemanticsData _button(WidgetTester tester, String tooltip) =>
    tester.getSemantics(find.byTooltip(tooltip)).getSemanticsData();

/// Every distinct photo has a distinct width, so order can be checked.
class _NumberedPicker extends ImagePickerPlatform {
  _NumberedPicker(this.count);
  final int count;

  @override
  Future<List<XFile>> getMultiImageWithOptions(
          {MultiImagePickerOptions options =
              const MultiImagePickerOptions()}) async =>
      [
        for (var i = 1; i <= count; i++)
          XFile.fromData(
            image.encodeJpg(image.Image(width: i, height: 4)),
            name: 'synthetic-$i.jpg',
            mimeType: 'image/jpeg',
          ),
      ];
}

/// Widths of the selected-photo thumbnails, in display order.
List<int> _thumbnailWidths(WidgetTester tester) => [
      for (final widget in tester.widgetList<Image>(find.byType(Image)))
        if (widget.image is MemoryImage)
          image.decodeJpg((widget.image as MemoryImage).bytes)!.width,
    ];

void main() {
  group('AUTH-201 notification bell', () {
    Future<ProviderContainer> showBell(
      WidgetTester tester, {
      required int unread,
      AppLanguage language = AppLanguage.english,
    }) async {
      final container = ProviderContainer(overrides: [
        unreadNotificationCountProvider.overrideWith((ref) async => unread),
        appLanguageProvider.overrideWith((ref) => language),
      ]);
      addTearDown(container.dispose);
      final router = GoRouter(routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => Scaffold(
            appBar: AppBar(actions: const [NotificationBell()]),
          ),
        ),
        GoRoute(
          path: '/notifications',
          builder: (_, __) => const Scaffold(body: Text('Inbox destination')),
        ),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ));
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('keeps its purpose with zero, one, many and large counts',
        (tester) async {
      final handle = tester.ensureSemantics();
      for (final (count, name, badge) in [
        (0, 'Notifications', null),
        (1, 'Notifications, 1 unread', '1'),
        (6, 'Notifications, 6 unread', '6'),
        (150, 'Notifications, 150 unread', '99+'),
      ]) {
        await showBell(tester, unread: count);
        final data = _button(tester, name);
        expect(data.tooltip, name);
        expect(data.hasAction(SemanticsAction.tap), isTrue);
        // The badge number no longer replaces (or duplicates) the name.
        expect(data.label, isEmpty, reason: 'count $count');
        expect(
            tester.widget<Badge>(find.byType(Badge)).isLabelVisible, count > 0);
        if (badge != null) expect(find.text(badge), findsOneWidget);
      }
      handle.dispose();
    });

    testWidgets('follows the count and the language', (tester) async {
      final handle = tester.ensureSemantics();
      final container = await showBell(tester, unread: 6);
      expect(find.byTooltip('Notifications, 6 unread'), findsOneWidget);

      // Reading notifications refreshes the count.
      container.updateOverrides([
        unreadNotificationCountProvider.overrideWith((ref) async => 0),
        appLanguageProvider.overrideWith((ref) => AppLanguage.english),
      ]);
      container.invalidate(unreadNotificationCountProvider);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Notifications'), findsOneWidget);
      expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isFalse);
      handle.dispose();
    });

    testWidgets('is localized in Russian and Uzbek', (tester) async {
      final handle = tester.ensureSemantics();
      await showBell(tester, unread: 3, language: AppLanguage.russian);
      expect(_button(tester, 'Уведомления, непрочитанных: 3').label, isEmpty);
      await showBell(tester, unread: 0, language: AppLanguage.russian);
      expect(find.byTooltip('Уведомления'), findsOneWidget);
      await showBell(tester, unread: 3, language: AppLanguage.uzbek);
      expect(find.byTooltip('Bildirishnomalar, o‘qilmagan: 3'), findsOneWidget);
      await showBell(tester, unread: 0, language: AppLanguage.uzbek);
      expect(find.byTooltip('Bildirishnomalar'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('opens the Notification Center by tap and keyboard',
        (tester) async {
      await showBell(tester, unread: 2);
      await tester.tap(find.byTooltip('Notifications, 2 unread'));
      await tester.pumpAndSettle();
      expect(find.text('Inbox destination'), findsOneWidget);

      await showBell(tester, unread: 2);
      final button = find.descendant(
        of: find.byType(NotificationBell),
        matching: find.byType(IconButton),
      );
      Focus.of(tester.element(find.descendant(
              of: button, matching: find.byIcon(Icons.notifications_outlined))))
          .requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Inbox destination'), findsOneWidget);
    });
  });

  group('AUTH-202 photo removal buttons', () {
    Future<void> mountForm(
      WidgetTester tester,
      Widget form, {
      required int photos,
      AppLanguage language = AppLanguage.english,
    }) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final original = ImagePickerPlatform.instance;
      ImagePickerPlatform.instance = _NumberedPicker(photos);
      addTearDown(() => ImagePickerPlatform.instance = original);
      final container = ProviderContainer(overrides: [
        mushukistanApiProvider
            .overrideWithValue(MushukistanApi(client: FakeApiClient())),
        appLanguageProvider.overrideWith((ref) => language),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: form),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.add_photo_alternate_outlined));
      await tester.pumpAndSettle();
    }

    for (final (name, form) in [
      ('Adoption', const AdoptionPostCreateScreen()),
      ('Lost pet', const LostPetCreateScreen()),
    ]) {
      testWidgets('$name: one photo has a named removal button',
          (tester) async {
        final handle = tester.ensureSemantics();
        await mountForm(tester, form, photos: 1);
        final data = _button(tester, 'Remove photo 1 of 1');
        expect(data.hasAction(SemanticsAction.tap), isTrue);
        await tester.tap(find.byTooltip('Remove photo 1 of 1'));
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.close), findsNothing);
        handle.dispose();
      });

      testWidgets(
          '$name: each photo is named by position; removal keeps order '
          'and relabels', (tester) async {
        final handle = tester.ensureSemantics();
        await mountForm(tester, form, photos: 5);
        expect(_thumbnailWidths(tester), [1, 2, 3, 4, 5]);
        for (var i = 1; i <= 5; i++) {
          expect(find.byTooltip('Remove photo $i of 5'), findsOneWidget);
        }
        // Five-photo limit still disables adding more.
        expect(
          tester
              .widget<ButtonStyleButton>(find.ancestor(
                  of: find.byIcon(Icons.add_photo_alternate_outlined),
                  matching: find.byWidgetPredicate(
                      (widget) => widget is ButtonStyleButton)))
              .onPressed,
          isNull,
        );

        // Middle photo.
        await tester.tap(find.byTooltip('Remove photo 3 of 5'));
        await tester.pumpAndSettle();
        expect(_thumbnailWidths(tester), [1, 2, 4, 5]);
        for (var i = 1; i <= 4; i++) {
          expect(find.byTooltip('Remove photo $i of 4'), findsOneWidget);
        }
        expect(find.byTooltip('Remove photo 5 of 5'), findsNothing);

        // First photo.
        await tester.tap(find.byTooltip('Remove photo 1 of 4'));
        await tester.pumpAndSettle();
        expect(_thumbnailWidths(tester), [2, 4, 5]);

        // Last photo.
        await tester.tap(find.byTooltip('Remove photo 3 of 3'));
        await tester.pumpAndSettle();
        expect(_thumbnailWidths(tester), [2, 4]);

        // Repeated removal of the (new) first photo.
        await tester.tap(find.byTooltip('Remove photo 1 of 2'));
        await tester.pumpAndSettle();
        expect(_thumbnailWidths(tester), [4]);
        expect(_button(tester, 'Remove photo 1 of 1').label, isEmpty);
        handle.dispose();
      });
    }

    testWidgets('names are localized in Russian and Uzbek', (tester) async {
      await mountForm(tester, const AdoptionPostCreateScreen(),
          photos: 2, language: AppLanguage.russian);
      expect(find.byTooltip('Удалить фото 1 из 2'), findsOneWidget);
      expect(find.byTooltip('Удалить фото 2 из 2'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await mountForm(tester, const AdoptionPostCreateScreen(),
          photos: 2, language: AppLanguage.uzbek);
      expect(
          find.byTooltip('1-rasmni olib tashlash (2 tadan)'), findsOneWidget);
      expect(
          find.byTooltip('2-rasmni olib tashlash (2 tadan)'), findsOneWidget);
    });
  });

  group('AUTH-203 profile overflow', () {
    late FakeAuthRepository auth;

    Future<GoRouter> mountProfile(WidgetTester tester,
        {double width = 800}) async {
      tester.view.physicalSize = Size(width, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      auth = FakeAuthRepository(
        restoreResult: SessionRestoreSuccess(
          AuthSession.restored(accessToken: 'token', user: testUser()),
        ),
      );
      final container = ProviderContainer(overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        googleIdentityTokenProvider
            .overrideWithValue(FakeGoogleIdentityTokenProvider()),
        profileMeProvider.overrideWith((ref) async => UserProfileData(
              id: testUser().id,
              email: 'owner@example.com',
              registeredAt: DateTime.utc(2026, 7, 1),
              observationCount: 1,
              totalLikesReceived: 2,
              commentCount: 3,
              name: 'Synthetic Owner',
            )),
      ]);
      addTearDown(container.dispose);
      final router = GoRouter(initialLocation: '/profile', routes: [
        GoRoute(
          path: '/profile',
          builder: (_, __) => const ProfileScreen(),
          routes: [
            GoRoute(
              path: 'settings',
              builder: (_, __) =>
                  const Scaffold(body: Text('Settings destination')),
            ),
          ],
        ),
        GoRoute(
          path: '/feed',
          builder: (_, __) => const Scaffold(body: Text('Feed destination')),
        ),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ));
      await tester.pumpAndSettle();
      return router;
    }

    testWidgets('app bar has a direct Logout button, not a one-item menu',
        (tester) async {
      final handle = tester.ensureSemantics();
      await mountProfile(tester);
      expect(find.byTooltip('Profile actions'), findsNothing);
      expect(find.byTooltip('Settings'), findsNothing);
      final logout = find.byKey(const ValueKey('profile-logout'));
      expect(logout, findsOneWidget);
      expect(find.descendant(of: logout, matching: find.text('Logout')),
          findsOneWidget);
      expect(
          tester
              .getSemantics(logout)
              .getSemanticsData()
              .hasAction(SemanticsAction.tap),
          isTrue);
      // The only control named Settings is the page row that opens settings.
      expect(find.text('Settings'), findsOneWidget);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Settings destination'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('Saved posts has its own card, apart from own activity',
        (tester) async {
      await mountProfile(tester);
      final card = find.byKey(const ValueKey('profile-saved-posts-card'));
      expect(card, findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('Saved posts')),
          findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('My cat posts')),
          findsNothing);
      expect(find.text('Saved posts'), findsOneWidget);
    });

    testWidgets('on phones Logout is an icon button named Logout',
        (tester) async {
      await mountProfile(tester, width: 390);
      final logout = find.byKey(const ValueKey('profile-logout'));
      expect(logout, findsOneWidget);
      expect(tester.widget<IconButton>(logout).tooltip, 'Logout');
      expect(find.byTooltip('Profile actions'), findsNothing);
    });

    testWidgets('logout keeps its confirmation; Cancel stays signed in',
        (tester) async {
      await mountProfile(tester);
      await tester.tap(find.byKey(const ValueKey('profile-logout')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(auth.logoutCalled, isFalse);
      expect(find.byType(ProfileScreen), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('profile-logout')));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
          of: find.byType(AlertDialog), matching: find.text('Logout')));
      await tester.pumpAndSettle();
      expect(auth.logoutCalled, isTrue);
      expect(find.text('Feed destination'), findsOneWidget);
    });
  });

  group('AUTH-217 password visibility', () {
    late FakeAuthRepository auth;

    Future<void> mountAuthScreen(
      WidgetTester tester,
      Widget screen, {
      AppLanguage language = AppLanguage.english,
    }) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      auth = FakeAuthRepository();
      final container = ProviderContainer(overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        googleIdentityTokenProvider
            .overrideWithValue(FakeGoogleIdentityTokenProvider()),
        appLanguageProvider.overrideWith((ref) => language),
      ]);
      addTearDown(container.dispose);
      final router = GoRouter(routes: [
        GoRoute(path: '/', builder: (_, __) => screen),
        GoRoute(
          path: '/:rest(.*)',
          builder: (_, __) => const Scaffold(body: Text('Other route')),
        ),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ));
      await tester.pumpAndSettle();
    }

    TextField passwordField(WidgetTester tester) => tester
        .widgetList<TextField>(find.byType(TextField))
        .firstWhere((field) =>
            field.obscureText || field.decoration?.suffixIcon != null);

    for (final (name, screen) in [
      ('Login', const LoginScreen()),
      ('Register', const RegisterScreen()),
    ]) {
      testWidgets('$name: named Show/Hide password, state-aware, no submit',
          (tester) async {
        final handle = tester.ensureSemantics();
        await mountAuthScreen(tester, screen);
        // Initially masked and empty.
        expect(passwordField(tester).obscureText, isTrue);
        final show = _button(tester, 'Show password');
        expect(show.hasAction(SemanticsAction.tap), isTrue);
        expect(show.label, isEmpty);

        await tester.tap(find.byTooltip('Show password'));
        await tester.pumpAndSettle();
        expect(passwordField(tester).obscureText, isFalse);
        expect(find.byTooltip('Hide password'), findsOneWidget);
        expect(find.byTooltip('Show password'), findsNothing);

        await tester.tap(find.byTooltip('Hide password'));
        await tester.pumpAndSettle();
        expect(passwordField(tester).obscureText, isTrue);

        // Populated: the name never contains the typed text.
        await tester.enterText(
            find.byWidget(passwordField(tester)), 'synthetic-pass');
        await tester.pump();
        final populated = _button(tester, 'Show password');
        expect(populated.label, isNot(contains('synthetic-pass')));
        expect(populated.tooltip, 'Show password');
        expect(auth.loginCalls + auth.registerCalls, 0);
        handle.dispose();
      });
    }

    testWidgets('Login: keyboard activation toggles without submitting',
        (tester) async {
      await mountAuthScreen(tester, const LoginScreen());
      final eye = find.byTooltip('Show password');
      Focus.of(tester
              .element(find.descendant(of: eye, matching: find.byType(Icon))))
          .requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(passwordField(tester).obscureText, isFalse);
      expect(find.byTooltip('Hide password'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(passwordField(tester).obscureText, isTrue);
      expect(find.byTooltip('Show password'), findsOneWidget);
      expect(auth.loginCalls, 0);
    });

    testWidgets('names are localized in Russian and Uzbek', (tester) async {
      await mountAuthScreen(tester, const LoginScreen(),
          language: AppLanguage.russian);
      expect(find.byTooltip('Показать пароль'), findsOneWidget);
      await tester.tap(find.byTooltip('Показать пароль'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Скрыть пароль'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await mountAuthScreen(tester, const LoginScreen(),
          language: AppLanguage.uzbek);
      expect(find.byTooltip('Parolni ko‘rsatish'), findsOneWidget);
      await tester.tap(find.byTooltip('Parolni ko‘rsatish'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Parolni yashirish'), findsOneWidget);
    });
  });
}
