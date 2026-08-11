# Mushukistan Backend

This is the FastAPI backend for the Mushukistan MVP.

## Included
- FastAPI application shell
- Clean Architecture folder layout
- Feature-first module structure
- SQLAlchemy 2.x and Alembic scaffolding
- Pydantic v2 settings management
- Dependency injection entry points
- Structured logging setup
- `/api/v1/health` endpoint
- MVP authentication, users, cats, posts, feed, comments, likes, reports, moderation, leaderboards, and map places

## Run (local)
```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -e .[dev]
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

## Android Physical Device Development
- For a physical Android phone, the backend must be reachable from the phone over the local network.
- Run the backend on all interfaces:
  ```powershell
  uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
  ```
- If you use Docker Compose instead, the equivalent is:
  ```powershell
  docker compose up --build backend
  ```
  The compose file already publishes backend port `8000:8000`.
  Development uploads are stored in a persistent Docker volume mounted at `/app/.data/media`,
  so post images survive backend container restarts and rebuilds.
- The PC and phone normally need to be on the same local network.
- Build the APK with the PC's LAN IPv4 address, for example:
  ```powershell
  flutter build apk --debug --dart-define=MUSHUKISTAN_API_BASE_URL=http://192.168.1.50:8000
  ```
- `10.0.2.2` works only in the Android emulator.
- `localhost` on the phone means the phone itself, not the development PC.
- Windows Firewall must allow inbound TCP traffic on port `8000`.
- Local `http://` is for development only. Production deployments should use HTTPS.

## Auth Development Notes
- Password registrations now require email verification before login succeeds.
- In development (`APP_ENV=development`), the backend emits the verification token in logs and API responses so local flows can be tested without an email provider.
- Google sign-in requires a valid `GOOGLE_OAUTH_CLIENT_ID` that matches the client configuration used by the Flutter app.

## OSM Place Import
- After migrations are applied, seed Tashkent pet shops, veterinary clinics and shelters from the free OpenStreetMap/Overpass source:
  ```powershell
  python scripts/import_osm_places.py
  ```
- The importer reads `DATABASE_URL`, stores available `phone` / `contact:phone` / `mobile` values, and preserves the OSM object ID in `source_id`.

## Testing
- Run live database tests sequentially against a single validation database.
- Do not run multiple live pytest processes against the same validation database at the same time; the cleanup fixtures can deadlock.

