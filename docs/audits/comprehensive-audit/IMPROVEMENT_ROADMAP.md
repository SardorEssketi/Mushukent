# Improvement Roadmap (updated after phase 2)

Nothing here has been implemented. Each item cites a finding in TECHNICAL_FINDINGS.md. Effort: S under a day, M a few days, L over a week.

## Release blockers (fix before wider public release)
| Item | Finding | Why it blocks |
|---|---|---|
| Enforce blocking everywhere | F-01 | The feature exists and looks functional but protects nobody; store policies expect it for UGC |

Strongly recommended before growth marketing: F-02 + F-03 (throttling), F-12 (fail-open environment), F-16 (outage shown as logout).

## Stage 1 - Immediate fixes
| Item | Finding | Pri | Effort | Benefit | Depends on | Validate with |
|---|---|---|---|---|---|---|
| Hide/reject blocked users in feed, comments, likes, notifications, contact | F-01 | P1 | M | Real harassment protection | Product choice: hide vs. reject | `evidence/repro_f01_f02_f03.py::test_f01_block_effect` turns green; add comment/like/contact cases |
| Key rate limits by IP unless the token verifies; add per-IP ceiling | F-02 | P2 | S | Restores throttling on public reads | - | Random-token test returns 429 |
| Evict idle limiter keys | F-03 | P2 | S | Removes memory growth | F-02 | Store size returns to ~0 after window |
| Make `APP_ENV` fail-closed (default production-like or explicit allow-list) | F-12 | P2 | S | Prevents verification-token leak | - | Unset/typo env refuses to start or behaves as production |
| Keep signed-in shell on network/5xx errors | F-16 | P2 | M | Outages stop looking like logouts | - | Stop API in the browser run; header stays signed-in |
| Decide on phone exposure (login-gate or tap-through) | F-13 | P2 | M | Stops anonymous harvesting | Product decision | Anonymous `GET /lost-pets` no longer contains numbers |
| Restrict cat edits to creator/moderator or media-host URLs | F-14 | P2 | S | Stops vandalism/hotlinking | Product decision | Non-owner PATCH -> 403 |

## Stage 2 - High-impact improvements
| Item | Finding | Pri | Effort | Benefit | Depends on | Validate with |
|---|---|---|---|---|---|---|
| Run `pytest` and `flutter test` in CI; fix `black` | F-04 | P2 | S | Merges are gated | F-05 | Green CI on a clean runner |
| PostHog optional outside production; disable telemetry in tests | F-05 | P2 | S | Contributors and CI can start the app; suite far faster | - | 3 rate-limit tests pass without env; suite time |
| Disposable-Postgres service in CI for the 181 DB tests | F-11 | P3 | M | Real integration coverage | CI runner | Skipped count ~0 |
| Add `limit_req` on `/api/` and auth routes in nginx | F-09 | P3 | S | Defence in depth | - | Burst returns nginx 429/503 |
| Health check that touches the database (readiness) | F-18 | P3 | S | Outages visible to Docker/monitoring | - | Stop DB -> container unhealthy |
| Tolerate zero-photo rows | F-25 | P3 | S | One bad row cannot take down a list | - | Test with seeded row |
| Load test + Lighthouse/throttled mobile run | PERFORMANCE_REVIEW | P2 | M | Replaces predictions with data | - | Recorded p95 and LCP |

## Stage 3 - Maintainability
| Item | Finding | Pri | Effort | Benefit | Depends on | Validate with |
|---|---|---|---|---|---|---|
| Fix mypy errors, merge duplicate `ApiSuccess`, add mypy to CI | F-06 | P2 | M | Type safety | - | 0 errors |
| Move off `python-jose`; lift the `cryptography<50` pin | F-20 | P3 | M | Maintained JWT stack | Token compatibility tests | `pip-audit` clean for runtime deps |
| Cleanup queue/sweep for media orphans | F-07 | P3 | S | Privacy hygiene | - | Simulated R2 failure then retry |
| Authorization tests for the untested routes (follow-ups, devices, reports) | SECURITY_REVIEW | P2 | M | Systematic IDOR coverage | - | One non-owner test per mutating route |
| Remove duplicate `GET /users/me` calls | F-24 | P3 | S | Fewer requests | - | 1 call at start |
| Crash reporting for Flutter; scheduled DB backups with a restore drill | F-26 | P3 | M | Failures stop going unnoticed | Provider choice | Forced error appears in dashboard; restore tested |

## Stage 4 - Optional
| Item | Finding | Pri | Effort | Benefit | Validate with |
|---|---|---|---|---|---|
| Popular-feed partial index | F-21 | P3 | S | Linear-to-indexed ordering at scale | `EXPLAIN` shows index scan at 1M+ rows |
| "Zoom in for more" on map cap | F-22 | P3 | S | Honest UI | Visual check |
| 404 vs. retry states, unknown-route shell | F-17 | P3 | S | Cleaner dead ends | Screenshots |
| Refresh-token rotation and absolute lifetime | F-19 | P3 | M | Smaller leak window | Replay returns 401 |
| httpOnly-cookie sessions on web | F-08 | P3 | L | Smaller XSS blast radius | Needs approval (architecture) |
| Android: app links, `allowBackup`, shrink, fail-fast signing, lower Gradle heap | F-10 | P3 | M | Release hygiene | Emulator run + signed release build |
| Idempotency keys for create endpoints | F-23 | P3 | M | Duplicate protection for API clients | Parallel-submit test |
