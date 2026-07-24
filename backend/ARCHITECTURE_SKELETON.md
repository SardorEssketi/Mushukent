# Backend Skeleton Architecture

This file defines dependency direction for the backend skeleton.

## Layer direction
- `api/presentation` depends on `application` contracts.
- `application` depends on `domain` contracts.
- `domain` depends on no framework or infrastructure.
- `infrastructure` implements interfaces used by `application`.

## Feature-first layout
Each feature lives under `app/features/<feature>/` with four sublayers:
- `presentation/`
- `application/`
- `domain/`
- `infrastructure/`

## Cross-cutting modules
- `app/core/config.py`: settings and environment management.
- `app/core/container.py`: composition root and dependency wiring.
- `app/core/dependencies.py`: FastAPI dependency providers.
- `app/core/errors.py`: unified API error envelope handlers.
- `app/core/logging.py`: structured logging setup.

## Notes
- This skeleton intentionally contains no business/use-case logic.
- API route modules are stubs aligned to `docs/API.md` resource groups.
- Database models and migrations are intentionally deferred to feature implementation phase.

