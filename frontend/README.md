# Mushukistan Frontend Skeleton

This is the Flutter Android-first MVP skeleton.

## Included
- Feature-first folder structure
- Riverpod setup
- GoRouter route shell
- Material 3 theme scaffold
- Localization-ready structure
- Empty screens for MVP flows
- API client foundation
- Secure token storage
- Authentication vertical slice
- Authenticated application shell

## Not included
- Feed, map, cats, posts, comments, and moderation screens are still skeletons
- No feature-specific business logic outside authentication

## Run
```powershell
flutter pub get
flutter run
```

## Configuration
- Set the backend API base URL with `--dart-define=MUSHUKISTAN_API_BASE_URL=...`.
- In Android emulator debug runs, the app falls back to `http://10.0.2.2:8000/api/v1/` when no override is provided.
- Desktop debug runs fall back to `http://localhost:8000/api/v1/`.
- Secure token storage uses the platform secure storage plugin; no access token is stored in plain text preferences.

## Testing
- Unit and widget tests do not require a running backend.
- An optional live backend smoke test is available when `RUN_LIVE_BACKEND_TESTS=1` is set for `flutter test`.

