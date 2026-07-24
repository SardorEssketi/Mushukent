# Mushukent Backend Skeleton

This is a production-oriented backend skeleton for Mushukent MVP.

## Included
- FastAPI application shell
- Clean Architecture folder layout
- Feature-first module structure
- SQLAlchemy 2.x and Alembic scaffolding
- Pydantic v2 settings management
- Dependency injection entry points
- Structured logging setup
- `/api/v1/health` endpoint

## Not included
- No business logic
- No authentication implementation
- No feature implementation for posts/cats/comments/maps

## Run (local)
```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -e .[dev]
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

