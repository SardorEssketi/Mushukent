import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class LegalConsentText extends StatelessWidget {
  const LegalConsentText({
    super.key,
    required this.leadingText,
    required this.linkText,
    required this.trailingText,
    required this.route,
    required this.enabled,
  });

  final String leadingText;
  final String linkText;
  final String trailingText;
  final String route;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final baseStyle = Theme.of(context).textTheme.bodyLarge;
    final disabledColor = colorScheme.onSurface.withValues(alpha: 0.38);
    final linkStyle = baseStyle?.copyWith(
      color: enabled ? colorScheme.primary : disabledColor,
      decoration: TextDecoration.underline,
      decorationColor: enabled ? colorScheme.primary : disabledColor,
    );

    return Text.rich(
      TextSpan(
        style: baseStyle,
        children: [
          TextSpan(text: leadingText),
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: InkWell(
              onTap: enabled ? () => context.push(route) : null,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(linkText, style: linkStyle),
              ),
            ),
          ),
          TextSpan(text: trailingText),
        ],
      ),
    );
  }
}
