import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/core/theme/app_theme.dart';

/// Found on a real 360 dp wide Android phone: the English "Leaderboard" tab label wrapped to
/// "Leaderboar / d". Every language must keep the five labels on one line.
void main() {
  setUpAll(() async {
    // The app font is not loaded in widget tests by default; text widths would be wrong without it.
    final loader = FontLoader('Manrope')
      ..addFont(rootBundle.load('assets/fonts/Manrope.ttf'));
    await loader.load();
  });

  const sets = {
    'en': ['Feed', 'Map', 'Add', 'Leaderboard', 'Profile'],
    'ru': ['Лента', 'Карта', 'Добавить', 'Лидеры', 'Профиль'],
    'uz': ['Lenta', 'Xarita', 'Qo‘shish', 'Yetakchilar', 'Profil'],
  };
  for (final entry in sets.entries) {
    testWidgets('bottom navigation labels stay on one line (${entry.key})',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2436);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          bottomNavigationBar: NavigationBar(
            selectedIndex: 0,
            destinations: [
              for (final label in entry.value)
                NavigationDestination(
                    icon: const Icon(Icons.circle), label: label),
            ],
          ),
        ),
      ));
      for (final label in entry.value) {
        final height = tester.getSize(find.text(label)).height;
        expect(height, lessThan(20), reason: '$label wrapped to several lines');
      }
    });
  }
}
