import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

String? validatedPostAuthRedirect(String? value) {
  if (value == null || value.trim().isEmpty) {
    return null;
  }
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.hasScheme ||
      uri.hasAuthority ||
      !uri.path.startsWith('/') ||
      uri.path.startsWith('/login') ||
      uri.path.startsWith('/register') ||
      uri.path.startsWith('/auth-required') ||
      uri.path.startsWith('/auth-gate')) {
    return null;
  }
  return uri.toString();
}

String authenticationRequiredLocation(Uri intendedLocation) {
  final redirect =
      validatedPostAuthRedirect(intendedLocation.toString()) ?? '/feed';
  return Uri(
    path: '/auth-required',
    queryParameters: {'redirect': redirect},
  ).toString();
}

void requestAuthentication(BuildContext context) {
  final router = GoRouter.maybeOf(context);
  if (router == null) {
    return;
  }
  router.push(
    authenticationRequiredLocation(router.routeInformationProvider.value.uri),
  );
}

String authEntryLocation(String path, String? redirect) {
  final safeRedirect = validatedPostAuthRedirect(redirect);
  return Uri(
    path: path,
    queryParameters: safeRedirect == null ? null : {'redirect': safeRedirect},
  ).toString();
}
