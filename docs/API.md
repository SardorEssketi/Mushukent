API.md

Mushukistan API — Canonical MVP Specification

Version: 1.0 (MVP)
Base URL: /api/v1

Introduction
------------
This document is the canonical, human-readable API specification for the Mushukistan MVP. It describes each endpoint in sufficient detail for a backend engineer to implement FastAPI controllers, Pydantic models, and SQLAlchemy repositories without making additional design decisions.

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
    "name": "Sardor",
    "preferred_language": "en",
    "accept_terms": true,
    "accept_privacy": true
  }
- Validation rules (AuthRegister):
  - email: required, RFC-5322 compatible, max 254 chars
  - password: required, min 8 chars, max 128 chars
  - name: required, non-blank, max 100 chars
  - preferred_language: optional, one of en|uz|ru, defaults to en
  - accept_terms: required true
  - accept_privacy: required true
- Response model: AuthRegisterResponse (201 Created)
  Example response:
  {
    "success": true,
    "data": {
      "email": "user@example.com",
      "verification_required": true,
      "dev_verification_token": "<development-only-token>"
    }
  }
- Error examples:
  - 400: {"success":false, "error":{"code":"INVALID_PAYLOAD","message":"Invalid register payload","details":{...}}}
  - 409: {"success":false, "error":{"code":"EMAIL_ALREADY_EXISTS","message":"Email already registered."}}
- Rate limit: auth endpoints stricter: 10 req/min per IP
- Notes:
  - Password stored hashed with Argon2 or bcrypt.
  - Password accounts must verify email before first login.
  - `dev_verification_token` is exposed only in development builds for local testing.

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
      "user": {"id":"uuid","email":"user@example.com","name":"Sardor","preferred_language":"en"}
    }
  }
- Errors:
  - 401: {"success":false, "error":{"code":"INVALID_CREDENTIALS","message":"Invalid email or password."}}
  - 401: {"success":false, "error":{"code":"EMAIL_NOT_VERIFIED","message":"Please verify your email."}}
- Rate limit: 10 req/min per IP

3) POST /api/v1/auth/resend-verification
- Purpose: Re-issue an email verification token for an unverified password account.
- Auth: none
- Request:
  {"email":"user@example.com"}
- Response model: ResendVerificationResponse (200)
  Example response:
  {
    "success": true,
    "data": {
      "email": "user@example.com",
      "verification_required": true,
      "dev_verification_token": "<development-only-token>"
    }
  }
- Errors:
  - 400 INVALID_PAYLOAD
  - 404 USER_NOT_FOUND is not required for MVP; unknown/ineligible accounts may return the same success shape with a null development token or a no-op implementation
- Notes: Production sends a real email through the configured Resend Email API settings.
  - Clients shall disable the resend action for 60 seconds after each resend request to prevent duplicate email bursts.

4) POST /api/v1/auth/verify-email
- Purpose: Confirm a password account's email address.
- Auth: none
- Request:
  {"token":"<verification-token>"}
- Response model: VerifyEmailResponse (200)
  Example response:
  {
    "success": true,
    "data": {
      "verified": true,
      "email": "user@example.com"
    }
  }
- Errors:
  - 401 INVALID_VERIFICATION_TOKEN
  - 404 USER_NOT_FOUND

5) POST /api/v1/auth/google
- Purpose: Login via Google id_token
- Auth: none
- Request: {"id_token":"<google-id-token>","accept_terms":true,"accept_privacy":true}
- Validation: id_token required
- Response: same as login
- Errors: 401 INVALID_GOOGLE_TOKEN
- Notes:
  - Validate iss, expiry, and `aud` against one configured Google OAuth client ID on server.
  - If the Google email does not match an existing account, the backend creates the account only when Terms and Privacy acceptance are true.
  - Existing accounts with current legal acceptance may authenticate without resubmitting acceptance flags.
  - Existing accounts missing current legal acceptance must submit Terms and Privacy acceptance before login completes.
  - Google-authenticated accounts are considered verified immediately.

6) POST /api/v1/auth/logout
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
      "comment_count": 17,
      "preferred_language": "en",
      "allow_public_activity_view": true
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
{"success":true, "data": {"id":"uuid","name":"Sardor","avatar_url":"...","registered_at":"...","observation_count":12,"comment_count":17,"allow_public_activity_view":true}}
- Errors: 404 USER_NOT_FOUND
- Sorting/Filtering: none
- Rate limit: standard

3) PATCH /api/v1/users/me
- Purpose: Update profile fields
- Auth: Bearer required
- Request model: UserUpdate
  Example:
  {"name":"New Name","bio":"Updated bio","avatar_url":"https://.../avatar.jpg","preferred_language":"uz","allow_public_activity_view":true}
- Validation: name max 100, bio max 1000, avatar_url valid URL, preferred_language in en|uz|ru, phone_number must be empty or an Uzbekistan phone number stored as `+998 XX XXX XXXX`, telegram_username must be empty or 5-32 letters/numbers/underscores.
- Response: updated UserProfile
- Errors: 400, 401, 422 INVALID_PHONE_NUMBER when phone_number is not an Uzbekistan number
- Pydantic model: UserUpdate
- Notes: Avatar upload handled via image upload endpoint and provides URL.

4) DELETE /api/v1/users/me
- Purpose: Delete the authenticated user's own account.
- Auth: Bearer required
- Response: 204 No Content
- Behavior:
  - anonymize account email and remove password hash, profile phone, avatar URL, name, bio, legal acceptance timestamps, and last login;
  - set `users.is_active = false`;
  - future requests with the same token are rejected as disabled;
  - delete the user's likes;
  - hide and anonymize owned posts, comments, and lost-pet posts;
  - remove copied lost-pet phone numbers;
  - remove the user from cat creator, report reporter, and report handler links where possible;
  - attempt best-effort media cleanup for profile, post, and lost-pet media URLs.
- Errors: 401 UNAUTHORIZED, 403 ACCOUNT_DISABLED

5) POST /api/v1/users/{user_id}/block
- Purpose: Block another active user.
- Auth: Bearer required
- Response: 204 No Content
- Errors: 401 UNAUTHORIZED, 404 USER_NOT_FOUND, 422 VALIDATION_ERROR when blocking yourself

6) DELETE /api/v1/users/{user_id}/block
- Purpose: Remove a block created by the current user.
- Auth: Bearer required
- Response: 204 No Content

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
  - photo/photos (one to five files) required OR photo_url string
     - cat_id (uuid) OR new_cat object {name,status,canonical_location}
     - description string (max 2000)
     - status (cat_status)
     - latitude, longitude (required if client does not rely on EXIF GPS)
     - is_public boolean
  b) application/json (if photo already hosted): same fields but photo_url required
- Validation rules:
  - At least one of photo file(s) or photo_url must be provided
  - observation uploads support up to 5 photos
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
      "photo_urls":["https://r2..."],
      "description":"Saw this kitty...",
      "location": {"latitude":41.3, "longitude":69.2},
      "created_at":"2026-07-23T...",
      "like_count":0,
      "comment_count":0,
      "is_liked_by_me": false
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
- Privacy: returns 403 ACTIVITY_PRIVATE when the target user has disabled public activity viewing, except for the owner and moderators.

5) GET /api/v1/users/{user_id}/comments
- Purpose: list comments by a user
- Auth: optional
- Query: cursor, limit, order=asc|desc
- Response: GenericListResponse[CommentResponse]
- Pydantic: CommentResponse
- Privacy: returns 403 ACTIVITY_PRIVATE when the target user has disabled public activity viewing, except for the owner and moderators.

6) GET /api/v1/cats/{cat_id}/posts
- Purpose: list posts for a cat (history)
- Auth: optional
- Query: cursor, limit, sort=latest|oldest
- Response: GenericListResponse[PostListItem]

Feature: Feed
-------------
1) GET /api/v1/feed
- Purpose: global feed with optional nearby filtering. The feed returns normal observation items, lost pet items, and adoption items.
- Auth: optional
- Query params:
  - cursor, limit
  - filter: recent|popular|nearby|adoption (default recent)
  - lat, lon, radius_meters (required if filter=nearby)
- Sorting options:
  - recent: created_at desc
  - popular: like_count desc, then created_at desc
  - nearby: distance asc then created_at desc
- Response: GenericListResponse[FeedListItem]
- Observation items include `is_liked_by_me`, which is `true` only when the request includes a valid authenticated user token and that user has liked the post.
- Example response:
  {
    "success": true,
    "data": {
      "items": [
        {"item_type":"observation", ...postListItem},
        {
          "item_type":"lost_pet",
          "id":"uuid",
          "author":{"id":"user-uuid","name":"Sardor","avatar_url":null},
          "photo_url":"https://...",
          "thumb_url":"https://...",
          "photo_urls":["https://..."],
          "pet_name":"Mittens",
          "last_seen_location":{"latitude":41.3,"longitude":69.2},
          "additional_info":"Orange tabby, missing since evening.",
          "owner_phone_number":"+998 XX XXX XX XX",
          "owner_telegram_username":"sardor_dev",
          "comment_count":0,
          "created_at":"..."
        },
        {
          "item_type":"adoption",
          "id":"uuid",
          "author":{"id":"user-uuid","name":"Sardor","avatar_url":null},
          "photo_url":"https://...",
          "thumb_url":"https://...",
          "photo_urls":["https://..."],
          "pet_name":"Mittens",
          "additional_info":"Friendly indoor cat looking for a new home.",
          "owner_phone_number":"+998 XX XXX XX XX",
          "owner_telegram_username":"sardor_dev",
          "comment_count":0,
          "created_at":"..."
        }
      ],
      "next_cursor": "...",
      "limit": 20
    }
  }
- Validation: if filter=nearby require lat/lon and radius_meters<=5000 (MVP limit)

Feature: Lost Pets
------------------
1) POST /api/v1/lost-pets
- Purpose: Create a lost pet post from the Add flow.
- Auth: Bearer required
- Request: multipart/form-data
  - photos: one or more image files
  - pet_name: required text, max 100 chars
  - last_seen_location: JSON string {"latitude":41.3,"longitude":69.2}
  - owner_phone_publication_consent: required true
  - additional_info: optional text, max 2000 chars
- Validation:
  - authenticated user must have a non-empty phone_number on their profile
  - phone_number must use Uzbekistan format `+998 XX XXX XXXX`
  - pet_name is required
  - at least one photo is required
  - last_seen_location is required
  - owner_phone_publication_consent must be true because the profile phone number is displayed publicly
  - photo files use the same image constraints as observation uploads
  - maximum 5 photos
- Response model: LostPetResponse (201)
- Errors:
  - 401 UNAUTHORIZED
  - 403 PHONE_NUMBER_REQUIRED
  - 422 INVALID_PHONE_NUMBER
  - 400 INVALID_PAYLOAD
  - 422 INVALID_IMAGE

2) GET /api/v1/lost-pets
- Purpose: List public lost pet posts.
- Auth: optional
- Query params: limit, cursor, lat, lon, radius_meters, valid_for_map
- Notes: `valid_for_map=true` returns unresolved public records created in the last 30 days for map markers. Older records remain available in feed/detail unless deleted or resolved.
- Response: GenericListResponse[LostPetListItem]

3) GET /api/v1/lost-pets/{lost_pet_id}
- Purpose: Retrieve one lost pet post with all photo URLs and contact phone number.
- Auth: optional
- Response: LostPetResponse
- Errors: 404 LOST_PET_NOT_FOUND

Feature: Adoption Posts
-----------------------
1) POST /api/v1/adoption-posts
- Purpose: Create an adoption post from the Add flow for a pet that needs a good home.
- Auth: Bearer required
- Request: multipart/form-data
  - photos: one or more image files
  - pet_name: required text, max 100 chars
  - owner_phone_publication_consent: required true
  - additional_info: optional text, max 2000 chars
- Validation:
  - authenticated user must have a non-empty phone_number on their profile
  - phone_number must use Uzbekistan format `+998 XX XXX XXXX`
  - pet_name is required
  - at least one photo is required
  - no location is accepted or required
  - owner_phone_publication_consent must be true because the profile phone number is displayed publicly
  - photo files use the same image constraints as observation uploads
  - maximum 5 photos
- Response model: AdoptionPostResponse (201)
- Errors:
  - 401 UNAUTHORIZED
  - 403 PHONE_NUMBER_REQUIRED
  - 422 INVALID_PHONE_NUMBER
  - 400 INVALID_PAYLOAD
  - 422 INVALID_IMAGE

2) GET /api/v1/adoption-posts
- Purpose: List public adoption posts.
- Auth: optional
- Query params: limit, cursor
- Response: GenericListResponse[AdoptionPostListItem]

3) GET /api/v1/adoption-posts/{adoption_post_id}
- Purpose: Retrieve one adoption post with all photo URLs and contact phone number.
- Auth: optional
- Response: AdoptionPostResponse
- Errors: 404 ADOPTION_POST_NOT_FOUND

Feature: Places
---------------
1) GET /api/v1/places
- Purpose: fetch cat-support places for the map, sourced from free OpenStreetMap data and moderator/manual entries.
- Auth: optional
- Query params:
  - category: repeatable, one or more of pet_shop|veterinary|shelter
  - lat, lon, radius_meters for nearby filtering
  - bbox=minLon,minLat,maxLon,maxLat for viewport filtering
  - limit, default 100, max 200
- Response: GenericListResponse[PlaceListItem]
  Example response:
  {
    "success": true,
    "data": {
      "items": [
        {
          "id": "uuid",
          "name": "Vet Clinic",
          "category": "veterinary",
          "location": {"latitude": 41.3, "longitude": 69.25},
          "address": "Tashkent",
          "phone": "+998 XX XXX XX XX",
          "website": "https://example.com",
          "opening_hours": "Mo-Sa 09:00-18:00",
          "source": "osm",
          "source_id": "node/123",
          "verified_at": null,
          "distance_meters": 320.5
        }
      ],
      "next_cursor": null,
      "limit": 100
    }
  }
- Validation:
  - category must be a supported place category.
  - If radius_meters is provided, lat and lon are required.
  - If bbox is provided, it must be minLon,minLat,maxLon,maxLat.
- Notes:
  - Free source tags: amenity=veterinary, shop=pet, amenity=animal_shelter, animal_shelter=cat, animal_boarding=cat.
  - Read phone from `phone`, `contact:phone`, `mobile` or `contact:mobile`.
  - Do not call public Overpass from every mobile client. Import/cache places through backend storage and expose them through this endpoint.

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

3) POST /api/v1/lost-pets/{lost_pet_id}/comments
- Purpose: create a comment on a lost pet post
- Auth: Bearer
- Request/response: same shape as post comments, with `lost_pet_id` populated and `post_id` null.

4) GET /api/v1/lost-pets/{lost_pet_id}/comments
- Purpose: list comments for a lost pet post
- Auth: optional
- Query: cursor, limit, order=asc|desc (default asc)
- Response: GenericListResponse[CommentResponse]

5) POST /api/v1/adoption-posts/{adoption_post_id}/comments
- Purpose: create a comment on an adoption post
- Auth: Bearer
- Request/response: same shape as post comments, with `adoption_post_id` populated and `post_id` null.

6) GET /api/v1/adoption-posts/{adoption_post_id}/comments
- Purpose: list comments for an adoption post
- Auth: optional
- Query: cursor, limit, order=asc|desc (default asc)
- Response: GenericListResponse[CommentResponse]

7) DELETE /api/v1/comments/{comment_id}
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
 - Definition:
   - most_active: count of visible public posts
   - most_popular: sum of like_count across visible public posts
   - top_helpers: count of visible public posts associated with cats whose status is needs_help or injured
   - deterministic tie-breaking: score descending, then user ID ascending
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
 - Idempotency: duplicate open reports from the same reporter for the same target return the existing open report
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
