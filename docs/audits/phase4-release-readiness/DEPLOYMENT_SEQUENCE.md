# Recommended deployment sequence and rollback checks

Only after the blockers are cleared.

1. Back up the production database and confirm a restore works. Record the current image or commit.
2. Check the production `.env`: `APP_ENV=production`, `RATE_LIMIT_ENABLED=true`, `APP_DEBUG=false`, a strong `JWT_SECRET_KEY`. PostHog is optional.
3. Push the branch, confirm GitHub CI is green, merge per your process.
4. Deploy the backend first. This phase has no migrations (verify with `alembic current`). The backend works with old clients, except guests lose the Contact Owner button.
5. Smoke test: health; anonymous list has no `owner_phone_number`; signed-in detail does; blocked users are hidden; cat PATCH by a non-owner returns 403.
6. Deploy the web client, then submit the Android build once Android validation is done.
7. Watch error rates, 429 counts and login failures for 24 hours.

Rollback: redeploy the previous backend image (no schema change, so no database rollback), redeploy the previous web build, and keep the previous Android release available. After a rollback, check that the old client still shows contact buttons (the old server returns phones).
