import 'package:flutter/material.dart';

/// Mushukistan design tokens.
///
/// Identity: warm paper neutrals, a single persimmon accent (the "cat" colour),
/// and a deep teal for positive/found states. Semantic status colours are
/// always paired with an icon or label, never colour alone.
class AppPalette {
  const AppPalette._();

  // Neutrals (60%): warm paper.
  static const cream = Color(0xFFFAF6F1);
  static const warmSurface = Color(0xFFFFFDFA);
  static const surface = Color(0xFFFFFFFF);
  static const graphite = Color(0xFF211C19);
  static const graphiteMuted = Color(0xFF6B615A);
  static const line = Color(0xFFEBE2D9);

  // Accent (10%): persimmon. `terracottaDark` is the AA-safe text/button tone.
  static const terracotta = Color(0xFFE2603A);
  static const terracottaDark = Color(0xFFB8431F);

  // Secondary: deep teal.
  static const sage = Color(0xFF3F8F7F);
  static const sageDark = Color(0xFF1F6455);

  // Status.
  static const lost = Color(0xFFC62F3C);
  static const found = Color(0xFF1F7A5A);
  static const adoption = Color(0xFF8A5A1F);
  static const help = Color(0xFFD08A12);
}

class AppSpacing {
  const AppSpacing._();

  static const xxs = 2.0;
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const huge = 48.0;
}

class AppRadii {
  const AppRadii._();

  static const sm = 10.0;
  static const md = 14.0;
  static const lg = 20.0;
  static const control = 14.0;
  static const card = 20.0;
  static const sheet = 28.0;
  static const dialog = 28.0;
  static const pill = 999.0;
}

class AppWidths {
  const AppWidths._();

  static const compact = 560.0;
  static const readable = 760.0;
  static const wide = 1080.0;
}

/// Responsive breakpoints shared by the shell and adaptive screens.
class AppBreakpoints {
  const AppBreakpoints._();

  static const medium = 720.0; // tablets: navigation rail
  static const expanded = 1100.0; // desktop: extended rail

  static bool isMedium(double width) => width >= medium;
  static bool isExpanded(double width) => width >= expanded;
}

/// Motion tokens. Durations collapse to zero when the platform requests
/// reduced motion.
class AppMotion {
  const AppMotion._();

  static const fast = Duration(milliseconds: 150);
  static const base = Duration(milliseconds: 240);
  static const curve = Curves.easeOutCubic;

  static Duration of(BuildContext context, [Duration d = base]) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : d;
}
