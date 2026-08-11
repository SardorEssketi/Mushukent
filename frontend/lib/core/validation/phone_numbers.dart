const uzbekPhoneFormat = '+998 XX XXX XXXX';
const invalidUzbekPhoneMessage =
    'Use Uzbekistan phone format: +998 XX XXX XXXX.';

String? normalizeUzbekPhoneNumber(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  if (RegExp(r'[A-Za-z]').hasMatch(trimmed)) {
    return null;
  }

  final digits = trimmed.replaceAll(RegExp(r'\D'), '');
  if (!trimmed.startsWith('+') ||
      !digits.startsWith('998') ||
      digits.length != 12) {
    return null;
  }

  return '+998 ${digits.substring(3, 5)} ${digits.substring(5, 8)} ${digits.substring(8, 12)}';
}

bool isValidUzbekPhoneNumber(String value) {
  return normalizeUzbekPhoneNumber(value) != null;
}

String dialablePhoneNumber(String value) {
  return value.replaceAll(RegExp(r'\s+'), '');
}
