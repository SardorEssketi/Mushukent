import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/core/theme/app_theme.dart';
import 'package:mushukistan_frontend/features/posts/presentation/widgets/publication_detail_parts.dart';

double _contrast(Color a, Color b) {
  final l1 = a.computeLuminance();
  final l2 = b.computeLuminance();
  final hi = l1 > l2 ? l1 : l2;
  final lo = l1 > l2 ? l2 : l1;
  return (hi + 0.05) / (lo + 0.05);
}

/// Regression test for a defect found on a real Android device: the label and the revealed number
/// on the primary Contact Owner button used the default text colour, which is dark on the orange
/// fill and made the phone number almost unreadable.
void main() {
  for (final theme
      in {'light': AppTheme.light, 'dark': AppTheme.dark}.entries) {
    testWidgets('primary contact button text is readable (${theme.key} theme)',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: theme.value,
        home: Scaffold(
          body: PublicationContactButton(
            icon: Icons.phone_outlined,
            label: 'Contact Owner',
            value: '+998 90 123 45 67',
            onPressed: () {},
          ),
        ),
      ));
      final scheme = theme.value.colorScheme;
      final label = tester.widget<Text>(find.text('Contact Owner'));
      final number = tester.widget<Text>(find.text('+998 90 123 45 67'));
      for (final text in [label, number]) {
        expect(text.style?.color, scheme.onPrimary);
        expect(_contrast(text.style!.color!, scheme.primary), greaterThan(3.0));
      }
    });
  }

  testWidgets('secondary contact button uses the primary colour for text',
      (tester) async {
    final theme = AppTheme.light;
    await tester.pumpWidget(MaterialApp(
      theme: theme,
      home: Scaffold(
        body: PublicationContactButton(
          primary: false,
          icon: Icons.alternate_email,
          label: 'Telegram',
          value: '@owner_handle',
          onPressed: () {},
        ),
      ),
    ));
    expect(tester.widget<Text>(find.text('Telegram')).style?.color,
        theme.colorScheme.primary);
  });
}
