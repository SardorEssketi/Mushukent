import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class LegalAgreementText extends StatelessWidget {
  const LegalAgreementText({
    super.key,
    required this.prefixText,
    required this.betweenText,
    required this.firstLinkText,
    required this.secondLinkText,
    required this.suffixText,
    required this.enabled,
  });

  final String prefixText;
  final String betweenText;
  final String firstLinkText;
  final String secondLinkText;
  final String suffixText;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textStyle = Theme.of(context).textTheme.bodyMedium;
    final linkColor = enabled
        ? colorScheme.primary
        : colorScheme.onSurface.withValues(alpha: 0.38);
    final linkStyle = textStyle?.copyWith(
      color: linkColor,
      decoration: TextDecoration.underline,
      decorationColor: linkColor,
    );

    InlineSpan link(String text, String route) => WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: InkWell(
            onTap: enabled ? () => context.push(route) : null,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Text(text, style: linkStyle),
            ),
          ),
        );

    return Text.rich(
      TextSpan(
        style: textStyle,
        children: [
          TextSpan(text: prefixText),
          link(firstLinkText, '/legal/terms'),
          TextSpan(text: betweenText),
          link(secondLinkText, '/legal/privacy'),
          TextSpan(text: suffixText),
        ],
      ),
    );
  }
}
