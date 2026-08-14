# Mushukistan Monorepo

This repository contains the Mushukistan MVP backend, Flutter client, canonical
documentation, and deployment scaffolding.

## Top-level layout
- `backend/` FastAPI + SQLAlchemy + Alembic backend
- `frontend/` Flutter + Riverpod + GoRouter client
- `docs/` canonical architecture/product documentation
- `infrastructure/` Nginx config and deployment docs
- `.github/` CI workflow
- `docker-compose.yml` local orchestration for backend + PostgreSQL/PostGIS + Nginx

## Backend local setup
The backend requires Python 3.13 or newer, matching CI.

```powershell
cd backend
py -3.13 --version
py -3.13 -m venv .venv
.\.venv\Scripts\Activate.ps1
python --version
python -m pip install --upgrade pip
python -m pip install -e ".[dev]"
$env:APP_ENV="development"
pytest
ruff check .
```

The repository `.env` is ignored by Git and may contain production-like
deployment settings. Local backend tests should run with `APP_ENV=development`.

