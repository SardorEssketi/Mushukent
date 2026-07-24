# Frontend Skeleton Architecture

This file defines architectural boundaries for the Flutter skeleton.

## Feature-first layout
Each feature is organized as:
- `presentation/` (widgets/screens only)
- `application/` (state/use-case orchestration placeholders)
- `domain/` (entities/value objects placeholders)
- `infrastructure/` (datasource/repository placeholders)

## Routing and navigation
- GoRouter is configured in `lib/core/routing/app_router.dart`.
- Route paths reflect the MVP screens listed in `docs/UI_UX.md`.

## State management
- Riverpod provider scope is established in `lib/main.dart`.
- No business logic providers are implemented yet.

## Theming and localization
- Material Design 3 theme shell in `lib/core/theme/app_theme.dart`.
- Localization-ready scaffold in `lib/core/localization/l10n.dart`.

## Notes
- Skeleton uses placeholder screens only.
- No API calls, auth logic, map logic, or domain behavior is implemented.

