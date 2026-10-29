# Mushukistan: instructions for Claude Code

Follow `AGENTS.md` (documentation is the source of truth, MVP-first, no architecture
changes without approval, small commits).

## Deployment: read before ANY deploy, release, or production command

1. Read `docs/DEPLOYMENT.md`, section **"Agent runbook: read this first"**, in full.
   Do not rely on memory or earlier conversations. It lists verified facts, unknowns,
   the procedures, rollback, and troubleshooting.
2. Deploy only when the user asks in this conversation, and ask again before every
   production-changing step. Never deploy as a side effect of another task.
3. Never guess SSH targets, container names, release paths, or env vars. The SSH target is in the
   gitignored `scripts/deploy/local.env` (`bash scripts/deploy/ssh-target.sh`; the repo is public). If the runbook
   marks it unknown, ask the user.
4. Never print, commit, or overwrite `.env`, keystores, `key.properties`, Firebase or
   OAuth secrets. Never remove DB/media volumes, run `alembic downgrade`, `docker compose
   down -v`, or `docker compose up --build` on the production host without explicit approval.
5. Use the scripts in `scripts/deploy/` (dry-run by default; they need a human-typed
   confirmation). Test them with `bash scripts/deploy/test_deploy_scripts.sh`.
6. Agent SSH to production is permission-gated. Root SSH is owner-only: the agent uses it
   only for read-only inspection the user has allowed (`scripts/deploy/remote-inspect.sh`),
   and every production-changing root command is run by the user (`! ssh -t ...`). The
   approval-based web automation is installed (`docs/DEPLOYMENT_AUTOMATION.md`, section 13):
   the agent may run `release-web` `status`, `health`, `tls`, `approvals`, `history`,
   `prepare` and `cancel`, and `deploy`/`rollback` for an approval the owner signed for that
   release. Only the owner runs `approve`, `approve-rollback` and `revoke`; never read or use
   the approval key. A full (activating) release still needs the user's explicit go-ahead
   for that commit. If anything is denied, do not work around it; ask the user.
7. After a release, update the facts in the runbook that changed (active release path,
   Alembic revision) and report each flow as VERIFIED, FAILED, or NOT VERIFIED.
8. Release branch is `main` (owner decision). Release only a pushed, CI-green `main` commit;
   never activate old staged release directories; every production change needs the user's
   explicit approval for that commit (approval gates G0-G6 in the runbook).
9. Never build Docker images on the production VPS (small host): use
   `scripts/deploy/build-backend-image.sh` locally and `docker load` on the server.
10. The hosting provider is unverified until the user confirms it.
11. The repository is public: never commit host addresses, backup inventories, row counts, hardening notes or
    secrets. Private production facts live in the gitignored `docs/private/PRODUCTION_STATE.md`.
