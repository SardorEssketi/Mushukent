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
cd backend
py -3.13 --version
py -3.13 -m venv .venv
.\.venv\Scripts\Activate.ps1
python --version
python -m pip install --upgrade pip
python -m pip install -e ".[dev]"
$env:APP_ENV="development"
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

The backend requires Python 3.13 or newer, matching CI and `pyproject.toml`.
If an existing local `.venv` reports Python 3.12, treat it as stale and create
a new virtual environment with Python 3.13. Do not commit virtual environments
or machine-specific `.env` files.

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
- Google sign-in requires `GOOGLE_OAUTH_CLIENT_ID` to include every OAuth client
  ID whose ID tokens the backend should accept. Use a comma-separated list when
  web and Android builds use different client IDs.

## OSM Place Import
- After migrations are applied, seed Tashkent pet shops, veterinary clinics and shelters from the free OpenStreetMap/Overpass source:
  ```powershell
  python scripts/import_osm_places.py
  ```
- The importer reads `DATABASE_URL`, stores available `phone` / `contact:phone` / `mobile` values, and preserves the OSM object ID in `source_id`.

## Manual Place Import
- Prepared Excel/CSV files can be imported through an administrative script. This is not a public API endpoint.
- Supported columns:
  `name`, `type`, `latitude`, `longitude`, `address`, `phone`, `phone 2`, `instagram`, `telegram`, `opening_hours`, `days_off`, `website`, `description`.
- Supported `type` aliases:
  `pet store` / `pet shop`, `veterinary clinic` / `veterinary` / `vet`, `animal shelter` / `shelter`.
- Combined types are comma-separated and import as one place with multiple categories, for example `pet store,vet`.
- Validate the local file without writing to the database:
  ```powershell
  python scripts/import_manual_places.py ..\Mushukistan_map.xlsx --dry-run
  ```
- Local import after Alembic migrations:
  ```powershell
  python scripts/import_manual_places.py ..\Mushukistan_map.xlsx
  ```
- Production import command, after explicit approval and with production `DATABASE_URL` already set in the shell:
  ```powershell
  python scripts/import_manual_places.py /path/to/Mushukistan_map.xlsx
  ```
- Duplicate protection uses a stable key built from normalized name, full category set, latitude and longitude. Re-running the same file skips previously imported rows.

## Testing
Use the Python 3.13 backend environment:
```powershell
cd backend
.\.venv\Scripts\Activate.ps1
python --version
$env:APP_ENV="development"
pytest
ruff check .
```

The pytest harness sets `APP_ENV` to `development` during test collection, so
local tests do not depend on production `.env` values. Setting it explicitly in
PowerShell keeps the test mode visible in the command history and avoids
surprises when running individual tests.

- Run live database tests sequentially against a single validation database.
- Do not run multiple live pytest processes against the same validation database at the same time; the cleanup fixtures can deadlock.

