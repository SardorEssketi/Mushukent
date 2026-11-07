import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../localization/app_strings.dart';
import '../network/api_error.dart';
import 'app_surface.dart';

/// Whether loading a publication failed for good, so retrying cannot help.
///
/// A detail endpoint answers 404 with its own code ([notFoundCode], such as
/// `POST_NOT_FOUND`) for a missing, deleted, moderator-removed, private or
/// blocked publication; it does not say which (docs/API.md). A malformed id is
/// rejected as a validation error. Any other failure (network, server, a 404
/// without that code from a proxy or an older server) stays retryable.
bool isPublicationUnavailable(Object error, String notFoundCode) {
  if (error is! MushukistanApiException) return false;
  return (error.kind == ApiFailureKind.notFound &&
          error.code == notFoundCode) ||
      error.kind == ApiFailureKind.validation;
}

/// Terminal state of a publication that cannot be shown: a neutral
/// explanation and a way out instead of Retry. Back keeps working.
class PublicationUnavailablePanel extends StatelessWidget {
  const PublicationUnavailablePanel({super.key, required this.strings});

  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return AppStatePanel(
      icon: Icons.visibility_off_outlined,
      title: strings.publicationUnavailableTitle,
      message: strings.publicationUnavailableMessage,
      action: FilledButton(
        onPressed: () => context.go('/feed'),
        child: Text(strings.goToFeed),
      ),
    );
  }
}
