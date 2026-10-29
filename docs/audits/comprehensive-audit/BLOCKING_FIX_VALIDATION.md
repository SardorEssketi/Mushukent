# Blocking fix: validation record (finding F-01)

Branch `fix/user-blocking` (4 commits on top of `dee71f4`). Policy and design: `docs/BLOCKING.md`.

## Automated tests
| Suite | Result |
|---|---|
| Backend, full suite on a disposable PostGIS container, final code | **395 passed, 1 skipped, 0 failed** (369 existing + 26 new) |
| New `backend/tests/test_blocking.py` | 26 passed. 8 of the key tests were run against the pre-fix code in a temporary git worktree and **all 8 failed** there |
| Flutter `flutter test` | **393 passed, 4 skipped** (385 before + 8 new) |
| `flutter analyze` | no issues |
| `ruff check app` | pass. `black --check`: only the pre-existing `app/main.py` finding (untouched). `mypy app`: 54 errors, same as before the change |

## Browser validation (Flutter Web release build, isolated backend, headless Chrome)
Executed with `evidence/bf_run1.py` and `evidence/bf_run2.py` (helpers `bfj.py`, seed `seed_bf.py`). Screenshots in `screenshots/blocking-fix/`.

Alice's session (19/19 checks): sees Bob's posts, lost pet and name before blocking; blocks Bob from his profile (snackbar "User blocked."); the already-open feed refreshes **without a page reload** and no longer contains any of Bob's content; same after a browser reload; direct URL to Bob's post shows nothing; the pre-block comment notification from Bob disappears from the inbox and the unread count drops 1 -> 0; Settings > Blocked users lists Bob; Unblock removes the row, shows "User unblocked.", and Bob's content is back in the feed and the unread count returns to 1.

Bob's session (11/11 checks): with Alice's lost-pet page already open and a comment typed, Alice blocks Bob; Bob's submit is rejected ("Lost pet post not found." shown inline, text kept, nothing stored, UI still usable); Bob's feed hides Alice's posts and lost pet but keeps Carol's and his own; direct URLs to Alice's content show nothing; after unblock everything returns.

## What was not verified
- Android (shared Dart code, but not run; the emulator could not start on this machine earlier in the audit).
- Real push delivery (worker behavior is covered by tests with a fake sender).
- Uzbek and Russian strings for the new screens were added and compile, but were not reviewed by a native speaker.
- Leaderboards and `GET /places` are intentionally not viewer-filtered (see `docs/BLOCKING.md`).
