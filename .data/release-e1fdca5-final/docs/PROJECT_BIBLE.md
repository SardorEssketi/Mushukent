Mushukistan Project Bible
1. Project Overview
Project Name

Mushukistan

Mission

Mushukistan is a Tashkent-focused social platform and interactive map for cat owners and the wider cat community.

The application combines cat records, observations, geolocation, nearby pet-care places, lost-pet alerts, adoption and rehoming posts, owner contact tools, and community interaction in one service.

Cats remain the central subject of the application, while observations, lost-pet alerts, and adoption posts give owners and community members practical ways to care for and find homes for cats.

2. Vision

The long-term vision of Mushukistan is to become the most useful digital home for cat owners and the cat community in Uzbekistan.

The application should:

help owners find nearby veterinary clinics, pet shops, and shelters;
help reunite lost pets with their owners;
support responsible adoption and rehoming;
preserve the history of cats and their observations;
encourage helpful local community participation;
provide useful geographical information about cats and pet-care places in Tashkent.
3. Target Platforms
MVP
Android
Future Versions
Web
iOS

Android is always the first priority.

4. Core Principles

Every architectural decision must satisfy the following principles.

Simplicity over complexity.
Mobile-first architecture.
Scalable backend.
Modular design.
High performance.
Security by default.
Clean Architecture.
AI-ready architecture.

Temporary shortcuts that compromise architecture are not acceptable.

5. Tech Stack
Mobile

Flutter
flutter_map
OpenStreetMap

Backend

FastAPI (Python)

Database

PostgreSQL
PostgreSQL + PostGIS

Object Storage

Cloudflare R2

Reverse Proxy

Nginx

Deployment

Docker

Docker Compose

GitHub Actions

Hosting

Hetzner VPS

Future

Redis

RabbitMQ (if background jobs become necessary)

Dedicated AI Microservice

6. Architecture Principles

The project follows Clean Architecture.

Application layers:

Presentation

↓

Application

↓

Domain

↓

Infrastructure

Rules:

UI contains no business logic.
Database is never accessed directly from the UI.
Business rules belong inside services/use cases.
Components should be loosely coupled.
Every feature should be independently maintainable.
7. Product Philosophy

Mushukistan is not Instagram for cats.

The application is built around real cats, not around user posts.

Posts are observations.

Cats are entities.

One cat can have many observations.

The historical timeline of each cat is one of the application's most valuable features.

8. Data Model Philosophy

The database distinguishes between two main entities.

Cat

Represents a real cat tracked by the community.

Contains:

name
status
approximate age
first seen
current status
cover photo

One Cat can have many Posts.

Post

Represents one observation.

Contains:

photo
location
author
timestamp
description

One Post always belongs to one Cat.

Never merge these concepts.

The backend must remain provider-agnostic for maps and spatial visualization.

9. Product Scope

The current product includes:

Authentication
Interactive Map
Cat records and observations
Feed
Lost-pet alerts
Adoption and rehoming posts
Nearby veterinary clinics, pet shops, and shelters
Likes
Comments
User Profiles
Leaderboards
Profile settings and account lifecycle controls
Reports and moderation

These capabilities define the current product scope.

10. Future Scope

Future versions may include:

AI Cat Recognition
Automatic Similar Cat Suggestions
Cat Movement History
Badges
User Levels
Hotspots
Push Notifications
Analytics
Multi-city Support
11. Coding Standards
Backend
Python 3.13+
FastAPI
SQLAlchemy
Alembic
Pydantic
Ruff
Black

Rules:

Full type hints.
No duplicated code.
Small reusable functions.
Clear naming.
Production-ready code only.
Flutter

Architecture:

Feature First

State Management:

Riverpod

Navigation:

GoRouter

Models:

Freezed

json_serializable

Rules:

No business logic inside widgets.
Reusable components.
Responsive layouts.
Material Design 3.
12. UI Principles

The interface should be:

Minimalistic.
Fast.
Intuitive.
Map-first.
Responsive.

Navigation should require as few interactions as possible.

Avoid unnecessary animations.

Performance has higher priority than visual effects.

13. API Principles

REST API.

Versioned endpoints.

Example:

/api/v1/auth
/api/v1/users
/api/v1/cats
/api/v1/posts
/api/v1/comments

Rules:

JWT Authentication.
Consistent JSON responses.
Proper HTTP status codes.
Validation on every request.
14. Git Workflow

Main Branch

main

Development Branch

develop

Feature branches

feature/add-map

feature/profile

feature/comments

Bug fixes

bugfix/login

bugfix/feed
15. AI Philosophy

Artificial Intelligence must never make final decisions.

The current MVP does not perform cat matching. Each new observation receives an unnamed Unknown cat record automatically. Any future identification feature must remain an explicit, separately approved scope change.

AI should improve user experience, not replace user decisions.

16. Non-functional Requirements

The application should satisfy:

Fast startup time.
API response under 300 ms for common requests.
Stable performance on mid-range Android devices.
Secure authentication.
Secure image storage.
Automatic backups.
High availability.
Scalable architecture capable of serving at least 100,000 users without redesign.
17. Documentation Rules

Before implementing any feature:

Update PRD.
Update Database Design.
Update API Specification.
Update Architecture if necessary.
Only then begin implementation.

Documentation is the source of truth.

18. AI Assistant Instructions

When using AI assistants (ChatGPT, Claude, Gemini, Cursor, GitHub Copilot):

The assistant must:

follow this Project Bible;
follow the PRD;
avoid inventing undocumented features;
explain architectural trade-offs;
prefer maintainable solutions over shortcuts;
generate production-ready code;
preserve Clean Architecture;
ask questions if requirements are ambiguous.
19. Project Priorities

When making technical decisions, always prioritize in this order:

Correctness
Maintainability
Scalability
Security
Performance
User Experience
Development Speed
