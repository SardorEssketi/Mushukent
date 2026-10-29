# Release hardening: blocking, rate limits, outage handling, contact privacy, CI

Draft only; nothing has been pushed.

## Summary
- Symmetric user blocking enforced on the surfaces listed in `docs/BLOCKING.md`
- Rate limiter keyed by verified identity/IP with bounded memory; fail-closed `APP_ENV`
- Optional, failure-proof PostHog analytics
- Session survives backend outages (retry screen, bounded back-off); language persisted locally
- Owner phone/Telegram hidden from guests and list/feed responses; cat edits restricted to creator or moderator
- CI: backend tests on PostGIS, Flutter analyze and tests, ruff and black

## Release notes for operators
- API behaviour change: guests no longer receive `owner_phone_number`; deploy backend and client together (see `docs/CONTACT_PRIVACY.md`)
- No database migrations in this series

## Test plan
- [x] Backend: 498 passed, 1 skipped (live R2) on disposable PostGIS
- [x] Flutter: analyze clean, tests passed
- [ ] GitHub Actions: all three jobs green
- [ ] Android runtime on a real device

See `docs/audits/final-release-gate/RELEASE_GATE.md`.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
