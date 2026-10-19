# Mushukistan: instructions for Claude Code

Follow `AGENTS.md` (documentation is the source of truth, MVP-first, no architecture
changes without approval, small commits).

## Deployment: read before ANY deploy, release, or production command

1. Read `docs/DEPLOYMENT.md`, section **"Agent runbook: read this first"**, in full.
   Do not rely on memory or earlier conversations. It lists verified facts, unknowns,
   the procedures, rollback, and troubleshooting.
2. Deploy only when the user asks in this conversation, and ask again before every
   production-changing step. Never deploy as a side effect of another task.
3. Never guess SSH targets, container names, release paths, or env vars. If the runbook
   marks it unknown, ask the user.
4. Never print, commit, or overwrite `.env`, keystores, `key.properties`, Firebase or
   OAuth secrets. Never remove DB/media volumes, run `alembic downgrade`, `docker compose
   down -v`, or `docker compose up --build` on the production host without explicit approval.
5. Use the scripts in `scripts/deploy/` (dry-run by default; they need a human-typed
   confirmation). Test them with `bash scripts/deploy/test_deploy_scripts.sh`.
6. Agent SSH to production may be blocked by the permission classifier. Do not work
   around it; give the user the exact command to run (`! ssh ...`) and ask for the output.
7. After a release, update the facts in the runbook that changed (active release path,
   Alembic revision) and report each flow as VERIFIED, FAILED, or NOT VERIFIED.
