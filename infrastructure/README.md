# Infrastructure Skeleton

This directory contains MVP infrastructure configuration.

## Included
- `docker-compose.yml` at repository root
- PostgreSQL + PostGIS service
- FastAPI backend service
- Nginx reverse proxy
- `.env.example` for environment configuration

## Out of scope (MVP)
- Redis
- RabbitMQ
- Background workers
- Monitoring stack (Prometheus/Grafana/ELK)
- AI services

## Quick start
```powershell
Copy-Item .env.example .env
docker compose up --build
```

## Notes
- This is a skeleton only. It provides deployable structure, not feature implementation.
- For production, HTTPS termination should be added at the edge or via a TLS-enabled proxy.

