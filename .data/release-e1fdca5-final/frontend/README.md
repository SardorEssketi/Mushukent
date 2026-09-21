# Mushukistan Flutter Client

This is the Android-first Flutter client for Mushukistan, a Tashkent-focused
app for cat owners and the wider cat community.

## Included
- Feature-first folder structure
- Riverpod state management
- GoRouter navigation shell
- Material 3 theme and localization
- Secure token storage and authenticated sessions
- Email and Google authentication with email verification
- Cat observations, feed, map, likes, comments, and cat matching flows
- Lost-pet and adoption/rehoming posts with owner contact actions
- Profiles, settings, legal pages, account deletion, leaderboards, reports, and moderation screens

## Run
```powershell
flutter pub get
flutter run
```

## Configuration
- Set the backend API base URL with `--dart-define=MUSHUKISTAN_API_BASE_URL=...`.
- Web Google sign-in uses `--dart-define=MUSHUKISTAN_GOOGLE_CLIENT_ID=<web-oauth-client-id>`.
- Android Google sign-in requires the Web OAuth client ID as
  `--dart-define=MUSHUKISTAN_GOOGLE_SERVER_CLIENT_ID=<web-oauth-client-id>`;
  `MUSHUKISTAN_GOOGLE_CLIENT_ID` alone is ignored by the Android plugin.
- In Android emulator debug runs, the app falls back to `http://10.0.2.2:8000/api/v1/` when no override is provided.
- Desktop debug runs fall back to `http://localhost:8000/api/v1/`.
- Secure token storage uses the platform secure storage plugin; no access token is stored in plain text preferences.

## Testing
- Unit and widget tests do not require a running backend.
- An optional live backend smoke test is available when `RUN_LIVE_BACKEND_TESTS=1` is set for `flutter test`.

