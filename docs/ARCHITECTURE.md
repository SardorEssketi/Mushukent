ARCHITECTURE.md
Mushukistan Architecture

Version 1.0

1. Overview

Mushukistan is a Tashkent-focused social platform and interactive map for cat owners and the wider cat community. It supports cat records and observations, nearby pet-care places, lost-pet alerts, adoption and rehoming posts, owner contact tools, and community features.

The system consists of several independent components communicating through REST APIs.

The architecture is designed for scalability, maintainability and future AI integration.

2. High Level Architecture
                   Android App
                  (Flutter)

                        │
                 HTTPS REST API

                        │

                 FastAPI Backend

        ┌───────────────┼────────────────┐
        │               │                │
        ▼               ▼                ▼

 PostgreSQL      Cloudflare R2      Authentication
  + PostGIS        (Images)            Service

                        │

                 Future AI Service
3. Components
Flutter Client

Responsibilities:

User Interface
GPS
Camera
Authentication
Map
Feed
Profiles
Upload Images

The Flutter application never communicates directly with the database.

All requests go through the Backend.

Map Architecture

The frontend renders maps with flutter_map and OpenStreetMap tiles.

The backend performs all spatial queries using PostgreSQL + PostGIS.

The backend stores only coordinates and never depends on a specific map provider.
There is no separate backend integration with OpenStreetMap or any other map renderer.

Map rendering is completely separated from the domain and API layers.

Dynamic map data is viewport-driven: the Flutter client sends the visible
south/west/north/east bbox after movement settles, and the backend applies
indexed PostGIS spatial predicates before returning lightweight marker fields.
The client keeps the previous marker set while a new viewport response is in
flight, debounces camera changes, ignores older responses, and briefly reuses
identical viewport responses. Needs-help and lost-pet markers remain in
dedicated alert groups.

Place pins are comparatively static. The client loads map-only place fields for
the supported Tashkent bounds by category, splits a bbox if the API's 200-row
limit is reached, and stores a versioned local snapshot for six hours. Cached
pins appear before a stale snapshot is refreshed in the background; a manual
Map refresh bypasses the age limit. Place details still come from the detail
endpoint when a marker is opened. Static places and dynamic content use
separate marker layers with zoom-aware clustering, so dynamic refreshes do not
reproject all place pins.

Future migration to Yandex Maps, Google Maps, MapLibre, or any other provider must require frontend changes only.

FastAPI Backend

Responsibilities:

Authentication
Business Logic
Validation
API
Image Upload
Database Access
Leaderboards
Moderation

Backend is the only component allowed to communicate with the database.

PostgreSQL

Stores:

Users
Cats
Posts
Likes
Comments
Reports
Persistent notifications and Android push delivery

PostGIS is used for:

Nearby searches
Radius filtering
Distance calculations
Cloudflare R2

Stores:

Original images
Compressed images
Future AI datasets

The database stores only image URLs.

Future AI Service

Responsibilities:

Detect cats
Generate embeddings
Compare cats
Suggest duplicate cats

The AI service never modifies the database directly.

It only returns recommendations.

4. Layered Architecture

Backend follows Clean Architecture.

Presentation

↓

Application

↓

Domain

↓

Infrastructure
Presentation

Contains:

REST Controllers
Request Validation
Response Models
Application

Contains:

Use Cases
Services
Business Logic

Examples:

Create Cat

Create Post

Like Post

Report Post

Domain

Contains:

Business Entities

Rules

Enums

Interfaces

No framework-specific code.

Infrastructure

Contains:

Database

Repositories

Storage

Cloudflare R2

External APIs

5. Feature Architecture

Each feature is independent.

Example:

features/

    auth/

    cats/

    posts/

    comments/

    likes/

    users/

    moderation/

    leaderboard/

Features should not depend on each other unless necessary.

6. User Flow
Registration
Open App

↓

Register

↓

Receive JWT

↓

Access Application
Upload Cat
Camera

↓

Take Photo

↓

GPS

↓

Fill Information

↓

Upload Image

↓

Create Post

↓

Visible on Map
View Cat
Open Map

↓

Select Marker

↓

Marker Preview

Cat records remain internal grouping entities in the MVP. Dedicated cat profile
pages are not required; users interact with observation posts, comments, and
likes from Feed and Map entry points.
7. Cat Recognition Flow

Current MVP

Take Photo

↓

Create unnamed cat with status Unknown

↓

Create observation linked to that cat

The MVP does not ask the user to match a nearby cat or choose existing/new.

Future AI

Take Photo

↓

AI verifies cat

↓

Nearby Cats

↓

Embedding Comparison

↓

Similarity Ranking

↓

User Confirms

↓

Post Created
8. Image Upload Flow
Flutter

↓

FastAPI

↓

Cloudflare R2

↓

Receive URL

↓

Store URL in PostgreSQL

↓

Return Success
9. Authentication Flow
Login

↓

JWT Access Token

↓

Authenticated Requests

↓

Backend Validation

↓

Response

Access Tokens should expire.

Opaque refresh sessions are part of the MVP. Refresh tokens are stored only by
the client, hashed in the database, renewed using the documented sliding
session behavior, and revoked on logout or account deletion.

10. Map Flow
User Location

↓

Backend Request

↓

Nearby Cats

↓

GeoJSON

↓

Flutter Map

↓

Markers
11. Database Relationships
User

│

├──── Posts

├──── Comments

├──── Likes

└──── Reports

Cat

│

└──── Posts

One Cat

↓

Many Posts

One User

↓

Many Posts

One Post

↓

Many Comments

12. Security

Every request must be validated.

Image uploads must be checked.

Rate limiting should be supported.

Passwords are never stored in plain text.

JWT required for protected endpoints.

13. Error Handling

Every endpoint returns:

Success

or

Error

Example:

{
    "success": false,
    "error": "CAT_NOT_FOUND"
}

Avoid returning internal exceptions to the client.

14. Logging

Backend should log:

Login attempts
Upload failures
Database errors
API exceptions
Moderation actions

Logs must never contain passwords or sensitive tokens.

15. Scalability

Designed to support:

100,000+ users
Millions of photos
Future AI service
Multiple cities

without redesigning the core architecture.

16. Notification Service and Future Expansion

Future services may include:

AI Service

↓

Notification Service (implemented; delivery requires Firebase configuration)

The authenticated notification API stores structured comment, direct-parent reply, and nearby Lost Pet events in PostgreSQL. It owns unread state, pagination, preferences, private alert points, and Android device-token registration. Comment and Lost Pet creation enqueue database delivery jobs in the same transaction as the source event; they do not call FCM. A separate Compose worker, running the same backend image, reads due follow-ups and seven-day inactivity cycles, claims delivery jobs with `FOR UPDATE SKIP LOCKED`, and calls FCM outside the originating action. Push retries are bounded to four attempts. Unknown/invalid tokens are retired. A restart may retry an ambiguously acknowledged send, so physical FCM delivery is best effort while event/job rows are deduplicated.

Nearby alert points are explicitly chosen, private, and matched to newly published Lost Pets with PostGIS geography `ST_DWithin` at a fixed 500 m. No background location tracking is used. Coarse authenticated launch/resume activity updates `users.last_active_at` at most once per 15 minutes. The worker adds 15 minutes of grace to the seven-day threshold so a throttled write cannot cause an early reminder. Inactivity is push-only and marked once per inactivity period. The existing Lost Pet/Rehoming follow-up rows remain authoritative; the worker only surfaces due rows by push. Android push requires externally provisioned Firebase client configuration, a private backend service-account file, and a token encryption key. Android FCM auto-initialization starts disabled and is enabled after device notification permission. Web has the in-app inbox, without Web Push.

↓

Analytics Service

↓

Admin Dashboard

↓

Web Application

Each new service should communicate through APIs and remain independent from the core backend.
