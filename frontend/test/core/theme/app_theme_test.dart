import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/core/theme/app_design_tokens.dart';
import 'package:mushukistan_frontend/core/theme/app_theme.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  for (final entry
      in {'light': AppTheme.light, 'dark': AppTheme.dark}.entries) {
    group('${entry.key} theme', () {
      final scheme = entry.value.colorScheme;

      test('text and action pairs meet WCAG AA contrast', () {
        final pairs = <String, (Color, Color)>{
          'onSurface/surface': (scheme.onSurface, scheme.surface),
          'onSurface/background': (
            scheme.onSurface,
            scheme.surfaceContainerLowest
          ),
          'onSurfaceVariant/surface': (scheme.onSurfaceVariant, scheme.surface),
          'onPrimary/primary': (scheme.onPrimary, scheme.primary),
          'primary/background': (scheme.primary, scheme.surfaceContainerLowest),
          'onPrimaryContainer/primaryContainer': (
            scheme.onPrimaryContainer,
            scheme.primaryContainer
          ),
          'onSecondaryContainer/secondaryContainer': (
            scheme.onSecondaryContainer,
            scheme.secondaryContainer
          ),
          'onError/error': (scheme.onError, scheme.error),
          'onInverseSurface/inverseSurface': (
            scheme.onInverseSurface,
            scheme.inverseSurface
          ),
        };
        pairs.forEach((name, pair) {
          expect(_contrast(pair.$1, pair.$2), greaterThanOrEqualTo(4.5),
              reason: name);
        });
      });

      test('uses the bundled brand typeface and 48dp controls', () {
        final theme = entry.value;
        expect(theme.textTheme.bodyMedium?.fontFamily, AppTheme.fontFamily);
        final size = theme.filledButtonTheme.style?.minimumSize?.resolve({});
        expect(size?.height, greaterThanOrEqualTo(48));
      });
    });
  }

  test('breakpoints switch navigation at tablet and desktop widths', () {
    expect(AppBreakpoints.isMedium(390), isFalse);
    expect(AppBreakpoints.isMedium(768), isTrue);
    expect(AppBreakpoints.isExpanded(768), isFalse);
    expect(AppBreakpoints.isExpanded(1440), isTrue);
  });
}
