ARCHITECTURE.md
Mushukistan Architecture

Version 1.0

1. Overview

Mushukistan is a location-based social network that allows users to photograph, discover and help street cats in Tashkent.

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
Notifications (future)

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

Cat Page

↓

History

↓

Comments

↓

Like
7. Cat Recognition Flow

Current MVP

Take Photo

↓

Nearby Cats (100–200 m)

↓

User chooses

Existing Cat

or

New Cat

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

Refresh Tokens may be added later.

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

16. Future Expansion

Future services may include:

AI Service

↓

Notification Service

↓

Analytics Service

↓

Admin Dashboard

↓

Web Application

Each new service should communicate through APIs and remain independent from the core backend.
