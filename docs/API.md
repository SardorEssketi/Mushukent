API.md

Mushukent API — Canonical MVP Specification

Version: 1.0 (MVP)
Base URL: /api/v1

Introduction
------------
This document is the canonical, human-readable API specification for the Mushukent MVP. It describes each endpoint in sufficient detail for a backend engineer to implement FastAPI controllers, Pydantic models, and SQLAlchemy repositories without making additional design decisions.

Global response envelope
------------------------
Success example:
{
  "success": true,
  "data": ...
}

Error example:
{
  "success": false,
  "error": {
    "code": "CAT_NOT_FOUND",
    "message": "Cat not found.",
    "details": { ... optional validation or debug info ... }
  }
}

Use this envelope consistently across all endpoints. Successful responses return HTTP 200/201/204 as appropriate. Error responses use appropriate HTTP status codes alongside the envelope.

Authentication
--------------
- Mechanism: JWT access token in Authorization header: "Authorization: Bearer <token>".
- For MVP: no refresh tokens. Clients re-authenticate when token expires.
- Protected routes will return 401 with error.code = "UNAUTHORIZED" for missing/invalid token and 403 with "FORBIDDEN" for insufficient permissions.

Rate limiting (MVP guidance)
----------------------------
- Global conservative default: 60 requests / minute per authenticated user; 30 requests / minute per IP for anonymous endpoints.
- Stricter limits on heavy endpoints: image upload and auth endpoints should be limited to 10 req/min per user or IP.
- Return 429 with error.code = "RATE_LIMIT_EXCEEDED" and Retry-After header when limit exceeded.

Pagination format
-----------------
- Cursor-based format (preferred):
  Request: ?limit=20&cursor=<opaque_cursor>
  Response data wrapper for lists:
  {
    "success": true,
    "data": {
      "items": [ ... ],
      "next_cursor": "<opaque_cursor_or_null>",
      "limit": 20
    }
  }
- For simple endpoints where offset is acceptable use ?limit & ?offset as fallback.
- Cursor encodes ordering key(s) (e.g., created_at + id).

Sorting and filtering
---------------------
- Sorting options are provided per endpoint. Use explicit query param `sort` with documented choices.
- Filtering uses query params (e.g., status=needs_help, filter=recently_seen).

Pydantic models (naming convention)
----------------------------------
Models in FastAPI should follow these names (examples below). Each endpoint references request/response models.
- AuthRegister, AuthLogin, AuthLoginResponse
- UserPublic, UserProfile, UserUpdate
- CatCreate, CatUpdate, CatResponse, CatListItem
- PostCreateMultipart (for multipart upload), PostCreateJSON (if photo_url already hosted), PostResponse, PostListItem
- FeedResponse
- CommentCreate, CommentResponse
- LikeResponse
- LeaderboardResponse
- ReportCreate, ReportResponse, ReportHandleRequest
- GenericListResponse[T]

Feature: Authentication
-----------------------
1) POST /api/v1/auth/register
- Purpose: Create a new user account.
- Auth: none
- Request model: AuthRegister
  Example request JSON:
  {
    "email": "user@example.com",
    "password": "P@ssw0rd1",
    "name": "Sardor"
  }
- Validation rules (AuthRegister):
  - email: required, RFC-5322 compatible, max 254 chars
  - password: required, min 8 chars, max 128 chars
  - name: optional, max 100 chars
- Response model: UserPublic (201 Created)
  Example response:
  {
    "success": true,
    "data": {
      "id": "11111111-1111-4111-8111-111111111111",
      "email": "user@example.com",
      "name": "Sardor",
      "registered_at": "2026-07-23T12:00:00Z"
    }
  }
- Error examples:
  - 400: {"success":false, "error":{"code":"INVALID_PAYLOAD","message":"Invalid register payload","details":{...}}}
  - 409: {"success":false, "error":{"code":"EMAIL_ALREADY_EXISTS","message":"Email already registered."}}
- Rate limit: auth endpoints stricter: 10 req/min per IP
- Notes: Password stored hashed with Argon2 or bcrypt.

2) POST /api/v1/auth/login
- Purpose: Login with email/password and receive JWT
- Auth: none
- Request model: AuthLogin
  Example:
  {"email":"user@example.com","password":"P@ssw0rd1"}
- Validation: email and password required
- Response model: AuthLoginResponse (200)
  Example response:
  {
    "success": true,
    "data": {
      "access_token": "eyJ...",
      "token_type": "Bearer",
      "expires_in": 3600,
      "user": {"id":"uuid","email":"user@example.com","name":"Sardor"}
    }
  }
- Errors:
  - 401: {"success":false, "error":{"code":"INVALID_CREDENTIALS","message":"Invalid email or password."}}
  - 401: {"success":false, "error":{"code":"EMAIL_NOT_VERIFIED","message":"Please verify your email."}}
- Rate limit: 10 req/min per IP

3) POST /api/v1/auth/google
- Purpose: Login via Google id_token
- Auth: none
- Request: {"id_token":"<google-id-token>"}
- Validation: id_token required
- Response: same as login
- Errors: 401 INVALID_GOOGLE_TOKEN
- Notes: Validate aud/iss and expiry with Google on server.

4) POST /api/v1/auth/logout
- Purpose: Logout; optional server-side token blacklist (not used in MVP)
- Auth: Bearer
- Request: none
- Response: 204 No Content
- Errors: 401
- Notes: Clients should drop token locally.

Feature: Users
--------------
1) GET /api/v1/users/me
- Purpose: Retrieve authenticated user's profile and aggregates
- Auth: Bearer required
- Response model: UserProfile
  Example response:
  {
    "success": true,
    "data": {
      "id": "uuid",
      "email": "user@example.com",
      "name": "Sardor",
      "avatar_url": "https://.../avatar.jpg",
      "bio": "Cat lover",
      "registered_at": "2026-07-01T10:00:00Z",
      "observation_count": 12,
      "total_likes_received": 45,
      "comment_count": 17
    }
  }
- Errors: 401 UNAUTHORIZED
- Pydantic model: UserProfile
- Rate limit: standard (60 req/min)

2) GET /api/v1/users/{user_id}
- Purpose: Get public profile
- Auth: optional
- Path param: user_id (UUID)
- Response model: UserPublic
  Example:
  {"success":true, "data": {"id":"uuid","name":"Sardor","avatar_url":"...","registered_at":"...","observation_count":12}}
- Errors: 404 USER_NOT_FOUND
- Sorting/Filtering: none
- Rate limit: standard

3) PATCH /api/v1/users/me
- Purpose: Update profile fields
- Auth: Bearer required
- Request model: UserUpdate
  Example:
  {"name":"New Name","bio":"Updated bio","avatar_url":"https://.../avatar.jpg"}
- Validation: name max 100, bio max 1000, avatar_url valid URL
- Response: updated UserProfile
- Errors: 400, 401
- Pydantic model: UserUpdate
- Notes: Avatar upload handled via image upload endpoint and provides URL.

Feature: Cats
-------------
1) POST /api/v1/cats
- Purpose: Create a Cat entity (user chooses new cat)
- Auth: Bearer required
- Request model: CatCreate
  Example:
  {
    "name": "Mittens",
    "status": "unknown",
    "approximate_age_smallyears": 3,
    "cover_photo_url": "https://r2.example/cats/abc.jpg",
    "canonical_location": {"latitude":41.3, "longitude":69.25}
  }
- Validation (CatCreate):
  - name optional max 100
  - status one of healthy|injured|needs_help|adopted|unknown|feed
  - approximate_age_smallyears nullable, 0-60
  - canonical_location lat/lon required pair if present
- Response model: CatResponse (201)
  Example:
  {
    "success": true,
    "data": {
      "id":"uuid",
      "name":"Mittens",
      "status":"unknown",
      "cover_photo_url":"...",
      "canonical_location": {"latitude":41.3, "longitude":69.25},
      "created_at":"..."
    }
  }
- Errors: 400, 401
- Rate limit: standard
- Pydantic model: CatCreate, CatResponse
- Notes: Creating a Cat does not create an observation automatically.

2) GET /api/v1/cats/{cat_id}
- Purpose: Cat page with aggregated stats and paginated observation history
- Auth: optional
- Path param: cat_id (UUID)
- Query params: limit, cursor, sort=latest|oldest (default latest)
- Response model: {
    id, name, status, cover_photo_url, first_seen_at, last_seen_at, total_observations, total_contributors, total_likes,
    observation_history: GenericListResponse[PostListItem]
  }
  Example response:
  {
    "success": true,
    "data": {
      "id":"...",
      "name":"Mittens",
      "status":"unknown",
      "cover_photo_url":"...",
      "first_seen_at":"2026-06-01T...",
      "last_seen_at":"2026-07-22T...",
      "total_observations": 12,
      "total_contributors": 5,
      "total_likes": 24,
      "observation_history": {
        "items": [ {postListItem}, ... ],
        "next_cursor": "...",
        "limit": 20
      }
    }
  }
- Errors: 404 CAT_NOT_FOUND
- Validation: cat_id must be UUID
- Pydantic models: CatResponse, PostListItem, GenericListResponse[PostListItem]

3) PATCH /api/v1/cats/{cat_id}
- Purpose: Update cat metadata
- Auth: Bearer required
- Authorization: moderators can change status and merged_into; normal users can suggest (for MVP allow users to update non-sensitive fields but require moderation for merges)
- Request model: CatUpdate
  Example:
  {"name":"New Name","status":"healthy","cover_photo_url":"..."}
- Validation: status must be enum
- Response: updated CatResponse
- Errors: 401, 403, 404
- Pydantic model: CatUpdate
- Notes: Merging two cats requires moderator action; set merged_into on source cat.

4) GET /api/v1/cats (search/list for map)
- Purpose: fetch cats by bounding box or nearby radius, with filters
- Auth: optional
- Query params (filters):
  - lat, lon, radius_meters (nearby)
  - bbox=minLon,minLat,maxLon,maxLat
  - filter: nearby|recently_seen|needs_help|recently_added
  - limit, cursor
- Sorting: by distance (if lat/lon provided), or last_seen_at desc
- Response: GenericListResponse[CatListItem]
  Example:
  {
    "success": true,
    "data": { "items": [ {catListItem}, ... ], "next_cursor": "...","limit":20 }
  }
- Validation: either radius OR bbox provided for geo queries; lat/lon ranges enforced
- Pydantic models: CatListItem
- Notes: Use PostGIS queries. Default limit: 20, max 100.

Feature: Posts (Observations)
-----------------------------
1) POST /api/v1/posts
- Purpose: Create an observation. Supports multipart upload for image or JSON when photo_url already exists.
- Auth: Bearer required
- Request options:
  a) multipart/form-data with file:
     - photo (file) required OR photo_url string
     - cat_id (uuid) OR new_cat object {name,status,canonical_location}
     - description string (max 2000)
     - status (cat_status)
     - latitude, longitude (required if client does not rely on EXIF GPS)
     - is_public boolean
  b) application/json (if photo already hosted): same fields but photo_url required
- Validation rules:
  - At least one of photo file or photo_url must be provided
  - If cat_id provided, must exist
  - If new_cat provided, validate per CatCreate
  - latitude in [-90,90], longitude in [-180,180]
  - photo file: content-type image/jpeg|image/png, size<=10MB
- Pydantic models: PostCreateMultipart (for docs), PostCreateJSON
- Example request (JSON variant):
  {
    "photo_url":"https://r2.example/buckets/abc.jpg",
    "cat_id": "uuid-of-cat",
    "description":"Saw this kitty near the market",
    "status":"healthy",
    "location": {"latitude":41.3, "longitude":69.2},
    "is_public": true
  }
- Example response (201):
  {
    "success": true,
    "data": {
      "id":"post-uuid",
      "cat_id":"...",
      "photo_url":"https://r2...",
      "thumb_url":"https://r2/...",
      "description":"Saw this kitty...",
      "location": {"latitude":41.3, "longitude":69.2},
      "created_at":"2026-07-23T...",
      "like_count":0,
      "comment_count":0
    }
  }
- Errors:
  - 400 INVALID_PAYLOAD
  - 401 UNAUTHORIZED
  - 422 INVALID_IMAGE
  - 409 DUPLICATE_OBSERVATION
- Transactional notes: for new_cat + post in same request, create both within one DB transaction and update cats counters.
- Rate limit: image-upload stricter (10 req/min)

2) GET /api/v1/posts/{post_id}
- Purpose: retrieve a single post with author and cat summary
- Auth: optional
- Response: PostResponse
  Example:
  {
    "success": true,
    "data": {
      "id":"post-uuid",
      "cat": {"id":"cat-uuid","name":"Mittens","cover_photo_url":"..."},
      "author": {"id":"user-uuid","name":"Sardor","avatar_url":"..."},
      "photo_url":"...",
      "thumb_url":"...",
      "description":"...",
      "location": {"latitude":41.3,"longitude":69.2},
      "created_at":"...",
      "like_count": 5,
      "comment_count": 2,
      "is_liked_by_me": true
    }
  }
- Errors: 404 POST_NOT_FOUND
- Pydantic model: PostResponse

3) DELETE /api/v1/posts/{post_id}
- Purpose: Soft-delete a post (owner or moderator)
- Auth: Bearer required
- Authorization: owner or moderator (403 otherwise)
- Request: none
- Response: 204 No Content (empty body) OR 200 with success envelope
- Errors: 401, 403, 404
- Side effects: decrement cat.total_observations, update counters transactionally
- Audit: record moderator_id if moderator deletes

4) GET /api/v1/users/{user_id}/posts
- Purpose: list posts by a user
- Auth: optional
- Query: cursor, limit, sort=latest|oldest
- Response: GenericListResponse[PostListItem]
- Pydantic: PostListItem

5) GET /api/v1/cats/{cat_id}/posts
- Purpose: list posts for a cat (history)
- Auth: optional
- Query: cursor, limit, sort=latest|oldest
- Response: GenericListResponse[PostListItem]

Feature: Feed
-------------
1) GET /api/v1/feed
- Purpose: global feed with optional nearby filtering
- Auth: optional
- Query params:
  - cursor, limit
  - filter: recent|popular|nearby (default recent)
  - lat, lon, radius_meters (required if filter=nearby)
- Sorting options:
  - recent: created_at desc
  - popular: like_count desc, then created_at desc
  - nearby: distance asc then created_at desc
- Response: GenericListResponse[PostListItem]
- Example response:
  {
    "success": true,
    "data": {
      "items": [ {postListItem}, ... ],
      "next_cursor": "...",
      "limit": 20
    }
  }
- Validation: if filter=nearby require lat/lon and radius_meters<=5000 (MVP limit)

Feature: Comments
-----------------
1) POST /api/v1/posts/{post_id}/comments
- Purpose: create a comment on a post
- Auth: Bearer
- Request model: CommentCreate
  Example:
  {"content":"So cute! Hope it's OK."}
- Validation: content required, max 1000 chars
- Response: CommentResponse (201)
  Example:
  {
    "success": true,
    "data": {
      "id":"comment-uuid",
      "post_id":"post-uuid",
      "user": {"id":"user-uuid","name":"Sardor"},
      "content":"So cute!",
      "created_at":"..."
    }
  }
- Side effects: increment post.comment_count
- Errors: 400, 401, 404
- Pydantic: CommentCreate, CommentResponse

2) GET /api/v1/posts/{post_id}/comments
- Purpose: list comments for a post
- Auth: optional
- Query: cursor, limit, order=asc|desc (default asc)
- Response: GenericListResponse[CommentResponse]

3) DELETE /api/v1/comments/{comment_id}
- Purpose: delete comment (owner or moderator)
- Auth: Bearer
- Response: 204 No Content
- Errors: 401,403,404
- Side effects: decrement post.comment_count

Feature: Likes
---------------
1) POST /api/v1/posts/{post_id}/likes
- Purpose: like a post
- Auth: Bearer
- Request: none
- Response: LikeResponse (200 or 201)
  Example:
  {"success": true, "data": {"liked": true, "like_count": 10}}
- Errors:
  - 401 UNAUTHORIZED
  - 404 POST_NOT_FOUND
  - 409 ALREADY_LIKED -> {"success": false, "error": {"code":"ALREADY_LIKED","message":"User already liked this post."}}
- Pydantic: LikeResponse
- Side effects: insert into likes table and increment posts.like_count transactionally

2) DELETE /api/v1/posts/{post_id}/likes
- Purpose: remove a like
- Auth: Bearer
- Response: 204 No Content or 200 with updated like_count
- Behavior: idempotent; deleting non-existing like returns 204

Feature: Leaderboards
---------------------
1) GET /api/v1/leaderboards/{type}
- Purpose: retrieve leaderboard
- Auth: optional
- Path param: type in [most_active, most_popular, top_helpers]
- Query params: period=day|week|month|all (default week), limit
- Response: LeaderboardResponse
  Example:
  {
    "success": true,
    "data": [
      {"rank":1,"user":{"id":"u1","name":"Alice"},"score":123},
      {"rank":2,...}
    ]
  }
- Notes: For MVP compute on read for small datasets; include optional leaderboard_cache for later optimization.
- Pydantic: LeaderboardResponse

Feature: Moderation
-------------------
1) POST /api/v1/reports
- Purpose: report inappropriate content
- Auth: Bearer
- Request model: ReportCreate
  Example:
  {
    "target_type":"post",
    "target_id":"post-uuid",
    "reason":"Contains graphic content",
    "metadata": {"screenshot_url":"https://..."}
  }
- Validation: target_type in post|comment|user|cat; target_id UUID; reason optional but recommended
- Response: ReportResponse (201)
- Errors: 400, 401, 404 (if target not found)
- Pydantic: ReportCreate, ReportResponse

2) GET /api/v1/moderation/reports
- Purpose: moderators list reports
- Auth: Bearer + moderator role
- Query: status=open|resolved|dismissed, limit, cursor
- Response: GenericListResponse[ReportResponse]
- Errors: 401, 403

3) PATCH /api/v1/moderation/reports/{report_id}
- Purpose: handle report and optionally take action
- Auth: Bearer + moderator
- Request model: ReportHandleRequest
  Example:
  {"status":"resolved","action":"soft_delete_post","note":"Removed spam"}
- Response: updated ReportResponse
- Errors: 401, 403, 404
- Side effects: any action (delete post, suspend user) must be recorded in an audit trail
- Pydantic: ReportHandleRequest

4) DELETE /api/v1/moderation/posts/{post_id}
- Purpose: moderator deletes content
- Auth: Bearer + moderator
- Response: 204 No Content
- Side effects: set deleted_at and record audit

Common error response examples
------------------------------
- 400 INVALID_PAYLOAD
  {"success":false,"error":{"code":"INVALID_PAYLOAD","message":"Missing required field: email"}}
- 401 UNAUTHORIZED
  {"success":false,"error":{"code":"UNAUTHORIZED","message":"Missing or invalid Authorization header."}}
- 403 FORBIDDEN
  {"success":false,"error":{"code":"FORBIDDEN","message":"You do not have permission to perform this action."}}
- 404 NOT_FOUND
  {"success":false,"error":{"code":"POST_NOT_FOUND","message":"Post not found."}}
- 409 CONFLICT
  {"success":false,"error":{"code":"EMAIL_ALREADY_EXISTS","message":"Email already registered."}}
- 422 VALIDATION_ERROR
  {"success":false,"error":{"code":"VALIDATION_ERROR","message":"Validation failed.","details":{"password":["too_short"]}}}
- 429 RATE_LIMIT_EXCEEDED
  {"success":false,"error":{"code":"RATE_LIMIT_EXCEEDED","message":"Too many requests."}}

Implementation notes for backend engineers
------------------------------------------
- Use Pydantic models listed above to validate request/response shapes and generate OpenAPI later.
- Use SQLAlchemy + Alembic for schema from docs/DATABASE.md. Use GeoAlchemy2 for geometry columns.
- Keep controllers thin; business logic sits in application/use-case layer.
- Transactions: use DB transactions where multi-table consistency is needed (create post + update cat counters, likes insert + increment like_count).
- Idempotency: POST endpoints that may be retried (image upload) should support idempotency keys if client desires; otherwise guard duplicates conservatively.
- Tests: implement unit tests for validation rules and integration tests for DB transactions.

Change log
----------
- 2026-07-23: Expanded API.md with full examples, validation, Pydantic model names and operational notes.
