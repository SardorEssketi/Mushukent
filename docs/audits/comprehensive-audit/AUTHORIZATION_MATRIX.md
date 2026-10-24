# Endpoint Authorization Matrix

Generated 2026-10-14 from the 81 routes in `backend/app/api/v1/routes/*` against a disposable PostGIS database (never the dev DB).
- **Declared auth** is derived from FastAPI dependencies (`get_current_active_user`/`get_current_user`/`require_moderator` = required; `get_optional_current_user` = optional; none = public).
- **Unauth actual** is the HTTP status of an unauthenticated request with random path IDs (evidence: `evidence/authz_matrix_tests.py::test_unauthenticated_sweep`).
- **Cross-user evidence** is from `test_ownership` (users A owner, B other user, M moderator). `-` means no dedicated cross-user test was run; ownership for those rows is by construction (acts only on the caller's own data) or is untested.

Result: all 53 routes that require authentication returned 401 unauthenticated. Every tested cross-user write was rejected (403/404) except cat editing (documented) and the block-related gaps.

| Method | Path | Declared auth | Unauth actual | Cross-user / role evidence |
|---|---|---|---|---|
| GET | `/api/v1/adoption-posts` | public | 200 | - |
| POST | `/api/v1/adoption-posts` | required | 401 | - |
| GET | `/api/v1/adoption-posts/follow-ups/due` | required | 401 | - |
| POST | `/api/v1/adoption-posts/follow-ups/{follow_up_id}/answer` | required | 401 | - |
| GET | `/api/v1/adoption-posts/mine` | required | 401 | - |
| DELETE | `/api/v1/adoption-posts/{adoption_post_id}` | required | 401 | B deletes A's adoption post -> 403 |
| GET | `/api/v1/adoption-posts/{adoption_post_id}` | optional | 404 | - |
| PATCH | `/api/v1/adoption-posts/{adoption_post_id}` | required | 401 | B edits A's adoption post -> 403 |
| POST | `/api/v1/adoption-posts/{adoption_post_id}/contact` | required | 401 | - |
| PATCH | `/api/v1/adoption-posts/{adoption_post_id}/resolution` | required | 401 | B resolves A's adoption post -> 403 |
| POST | `/api/v1/auth/change-password` | required | 401 | - |
| POST | `/api/v1/auth/google` | public | 422 | - |
| POST | `/api/v1/auth/login` | public | 422 | - |
| POST | `/api/v1/auth/logout` | required | 401 | - |
| GET | `/api/v1/auth/methods` | required | 401 | - |
| POST | `/api/v1/auth/refresh` | public | 422 | - |
| POST | `/api/v1/auth/register` | public | 422 | - |
| POST | `/api/v1/auth/resend-verification` | public | 422 | - |
| POST | `/api/v1/auth/verify-email` | public | 422 | - |
| GET | `/api/v1/cats` | public | 200 | - |
| POST | `/api/v1/cats` | required | 401 | - |
| GET | `/api/v1/cats/{cat_id}` | public | 404 | - |
| PATCH | `/api/v1/cats/{cat_id}` | required | 401 | non-owner B renames A's cat -> 200 (documented MVP, see F-14); non-mod status -> 403 |
| GET | `/api/v1/cats/{cat_id}/posts` | optional | 404 | - |
| GET | `/api/v1/adoption-posts/{adoption_post_id}/comments` | optional | 404 | - |
| POST | `/api/v1/adoption-posts/{adoption_post_id}/comments` | required | 401 | - |
| DELETE | `/api/v1/comments/{comment_id}` | required | 401 | B deletes A's comment -> 403 |
| PATCH | `/api/v1/comments/{comment_id}` | required | 401 | B edits A's comment -> 403 |
| GET | `/api/v1/lost-pets/{lost_pet_id}/comments` | optional | 404 | - |
| POST | `/api/v1/lost-pets/{lost_pet_id}/comments` | required | 401 | - |
| GET | `/api/v1/posts/{post_id}/comments` | optional | 404 | - |
| POST | `/api/v1/posts/{post_id}/comments` | required | 401 | blocked user comments on blocker's post -> 201 (F-01) |
| GET | `/api/v1/feed` | optional | 200 | garbage Bearer -> 401; blocked user's posts still returned (F-01) |
| POST | `/api/v1/feedback` | required | 401 | - |
| GET | `/api/v1/health` | public | 200 | - |
| GET | `/api/v1/leaderboards/{type}` | public | 422 | - |
| DELETE | `/api/v1/posts/{post_id}/likes` | required | 401 | - |
| POST | `/api/v1/posts/{post_id}/likes` | required | 401 | 20 concurrent likes same user -> 1x200 + 19x409, like_count=1; blocked user -> 200 (F-01) |
| GET | `/api/v1/lost-pets` | public | 200 | - |
| POST | `/api/v1/lost-pets` | required | 401 | - |
| GET | `/api/v1/lost-pets/follow-ups/due` | required | 401 | - |
| POST | `/api/v1/lost-pets/follow-ups/{follow_up_id}/answer` | required | 401 | - |
| GET | `/api/v1/lost-pets/map` | public | 422 | - |
| GET | `/api/v1/lost-pets/mine` | required | 401 | - |
| DELETE | `/api/v1/lost-pets/{lost_pet_id}` | required | 401 | B deletes A's lost pet -> 403 |
| GET | `/api/v1/lost-pets/{lost_pet_id}` | optional | 404 | - |
| PATCH | `/api/v1/lost-pets/{lost_pet_id}` | required | 401 | B edits A's lost pet -> 403 |
| POST | `/api/v1/lost-pets/{lost_pet_id}/contact` | required | 401 | blocked user B contacts owner -> 204 (expected rejection, F-01) |
| PATCH | `/api/v1/lost-pets/{lost_pet_id}/resolution` | required | 401 | B resolves A's lost pet -> 403 |
| DELETE | `/api/v1/moderation/posts/{post_id}` | moderator | 401 | normal user -> 403 |
| GET | `/api/v1/moderation/posts/{post_id}/history` | moderator | 401 | normal user -> 403 |
| GET | `/api/v1/moderation/reports` | moderator | 401 | normal user -> 403; moderator -> 200 |
| GET | `/api/v1/moderation/reports/{report_id}` | moderator | 401 | - |
| PATCH | `/api/v1/moderation/reports/{report_id}` | moderator | 401 | - |
| GET | `/api/v1/notifications` | required | 401 | - |
| POST | `/api/v1/notifications/activity` | required | 401 | - |
| POST | `/api/v1/notifications/devices` | required | 401 | - |
| POST | `/api/v1/notifications/devices/unregister` | required | 401 | - |
| GET | `/api/v1/notifications/preferences` | required | 401 | - |
| PATCH | `/api/v1/notifications/preferences` | required | 401 | - |
| POST | `/api/v1/notifications/read-all` | required | 401 | - |
| GET | `/api/v1/notifications/unread-count` | required | 401 | - |
| POST | `/api/v1/notifications/{notification_id}/read` | required | 401 | B marks A's notification -> 404; owner -> 204 |
| GET | `/api/v1/places` | public | 200 | - |
| GET | `/api/v1/places/{place_id}` | public | 404 | - |
| POST | `/api/v1/posts` | required | 401 | - |
| DELETE | `/api/v1/posts/{post_id}` | required | 401 | B deletes A's post -> 403 |
| GET | `/api/v1/posts/{post_id}` | optional | 404 | - |
| PATCH | `/api/v1/posts/{post_id}` | required | 401 | B edits A's post -> 403 |
| POST | `/api/v1/reports` | required | 401 | - |
| POST | `/api/v1/users/account-deletion-confirmations` | public | 422 | - |
| POST | `/api/v1/users/account-deletion-requests` | public | 422 | - |
| DELETE | `/api/v1/users/me` | required | 401 | after delete: token -> 403, like -> 403 |
| GET | `/api/v1/users/me` | required | 401 | - |
| PATCH | `/api/v1/users/me` | required | 401 | - |
| POST | `/api/v1/users/me/avatar` | required | 401 | - |
| GET | `/api/v1/users/{user_id}` | public | 404 | public profile keys exclude email/phone/telegram/is_moderator |
| DELETE | `/api/v1/users/{user_id}/block` | required | 401 | - |
| POST | `/api/v1/users/{user_id}/block` | required | 401 | stored, but not enforced elsewhere (F-01) |
| GET | `/api/v1/users/{user_id}/comments` | optional | 404 | activity-private owner, viewer B -> 403 |
| GET | `/api/v1/users/{user_id}/posts` | optional | 404 | activity-private owner, viewer B -> 403 |
