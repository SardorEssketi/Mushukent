Product Requirements Document (PRD)
Project

Mushukistan

Version: 1.0

Status: Draft

Author: Sardor Muxtorov

1. Overview
Product Description

Mushukistan is a Tashkent-focused social application and interactive map for cat owners and the wider cat community.

Users can record cats and observations, find nearby veterinary clinics, pet shops, and shelters, publish lost-pet alerts, create adoption and rehoming posts, contact owners, and participate in community discussions.

Mushukistan combines practical cat-care tools with community content. Cat records and observation histories remain important, while lost-pet and adoption/rehoming workflows address everyday needs of cat owners in Tashkent.

2. Problem Statement

There is currently no single local platform in Tashkent where cat owners and community members can:

find nearby veterinary clinics, pet shops, and shelters;
publish and discover lost-pet alerts;
help cats find new homes through adoption and rehoming posts;
document cats and preserve their observation history;
share useful locations and information with other cat owners;
discuss posts, report problems, and rely on community moderation.

As a result, valuable information is fragmented across social media platforms or lost entirely.

3. Product Vision

Build the most useful digital service for cat owners in Tashkent by combining cat-care information, lost-pet recovery, adoption and rehoming, local discovery, and community participation.

4. Goals

Primary goals:

Build a reliable platform for recording cats and observations.
Help owners find nearby pet-care places and useful local information.
Support lost-pet recovery and responsible adoption or rehoming.
Encourage helpful community participation and moderation.
Create a scalable platform that can later expand to other cities.
5. Success Metrics

The MVP will be considered successful if it achieves the following within the first six months after launch:

500+ registered users.
2,000+ published observations.
500+ unique cats recorded.
At least 30% monthly active users.
Average session duration greater than 4 minutes.
Less than 1% application crash rate.
API uptime above 99%.
6. Target Audience

Primary audience:

Cat owners in Tashkent
People searching for lost pets
People adopting or rehoming cats
Cat lovers and volunteers
Veterinary clinics, pet shops, and shelters
Animal welfare organizations
Other local community members

Age:

16–40 years old.

7. Product Value

Mushukistan provides users with the ability to:

record and discover cats and observations;
find nearby veterinary clinics, pet shops, and shelters;
publish and find lost-pet alerts;
create or browse adoption and rehoming posts;
contact owners when a post allows it;
participate in discussions, reports, leaderboards, and moderation;
manage profiles, privacy, language, and account settings.
8. User Stories
Cat Owner

As a cat owner, I want to share information about my cat or an observation so that the local community can help and participate.

Lost Pet Owner

As a cat owner, I want to publish a lost-pet alert with photos, location, and contact information so that people in Tashkent can help find my pet.

Adopter or Fosterer

As someone looking to adopt or rehome a cat, I want to browse adoption posts and contact the owner.

Cat Care Seeker

As a cat owner, I want to find nearby veterinary clinics, pet shops, and shelters so I can get help for a cat.

Cat Lover

As a cat lover, I want to browse nearby cats and community posts so I can discover and support local cats.

Explorer

As an explorer, I want to see where cats are located across the city.

Community Member

As a community member, I want to comment on observations and interact with other users.

9. Functional Requirements
Authentication

Users shall be able to:

register using email;
sign in using Google;
manage their profile;
choose a preferred app language after email verification and sign-in.

Email registration shall require a non-empty display name.

Email verification resend controls shall use a visible cooldown before the user can request another verification email.

Supported MVP languages:

English
Uzbek
Russian
Map

The application shall display an interactive OpenStreetMap with cat markers for all published cats.

Users shall be able to:

zoom;
move across the map;
select markers;
open cat pages;
view nearby cat-support places, including pet shops, veterinary clinics and animal shelters.

Available filters:

Nearby Cats
Recently Seen
Needs Help
Recently Added
Pet Shops
Veterinary Clinics
Animal Shelters

Place markers shall show available public contact details, including phone number, second phone number, website, Instagram, Telegram, opening hours, days off and description when present in the free source data or manually verified by moderators.
One real place may belong to more than one supported place category.
Cats and Observations

Users shall be able to create a new observation by providing:

photo;
description;
an optional current or manually selected location.

Each observation automatically receives an unnamed cat record with status Unknown. The observation flow does not ask the user to choose an existing cat or create/name a new cat.

Cat statuses:

Healthy
Injured
Needs Help
Adopted
Unknown
Feed

Users shall see nearby observations sorted by:

Distance
Publication date

Lost Pets

Users shall be able to view lost pet posts in the main feed with a distinct Lost Pet tag.

Users shall be able to create a lost pet post from the Add flow by providing:

one or more cat photos;
the pet's name;
last-seen GPS/map coordinates;
additional information;
the owner's phone number from their profile.

Users without a profile phone number may view lost pet posts, but must add a phone number before creating one.

Profile phone numbers used for lost pet contact shall use the Uzbekistan format `+998 XX XXX XXXX`. Invalid or non-Uzbek phone numbers shall be rejected with a clear validation message.

Lost pet posts shall include a Contact Owner action that initiates a phone call to the stored owner phone number.

Adoption Posts

Users shall be able to view adoption posts in the main feed with a distinct Adoption tag.

Users shall be able to create an adoption post from the Add flow when they want to give a pet to a good home by providing:

one or more cat photos;
the pet's name;
additional information;
the owner's phone number from their profile.

Adoption posts shall not require GPS/map coordinates and shall not appear as map markers.

Users without a profile phone number may view adoption posts, but must add a phone number before creating one.

Profile phone numbers used for adoption contact shall use the Uzbekistan format `+998 XX XXX XXXX`. Invalid or non-Uzbek phone numbers shall be rejected with a clear validation message.

Adoption posts shall include a Contact Owner action that initiates a phone call to the stored owner phone number.
Cat Records

Dedicated cat profile pages are not required for MVP. Cat records remain
internal grouping entities used for observation links, map markers, status,
and aggregate counters. Observation details remain accessible from Feed and
Map flows.
Posts

Each observation shall contain:

image;
author;
timestamp;
optional location;
description;
comments;
likes.
Comments

Users shall be able to:

create comments;
reply to comments with unlimited nesting;
delete their own comments.
Likes

Users shall be able to like and unlike observations.

A user may like an observation only once.

User Profile

Profiles shall display:

avatar;
number of observations;
total likes received;
comments count.

Registration date shall be shown in Profile settings under About account, not as a main profile stat.

Users shall be able to change their preferred app language later from Settings.

Users shall be able to delete their own account from Settings under About account.

MVP account deletion shall anonymize the account, deactivate login, end the current session, delete likes, and hide/anonymize user-owned posts, comments, lost-pet alerts, and adoption or rehoming posts according to the account lifecycle policy.
Leaderboards

The application shall include:

Most Popular Users

Most Active Users

Top Animal Helpers

MVP leaderboard definitions:

- Most Popular Users: count of visible public posts.
- Most Active Users: count of visible public posts.
- Top Animal Helpers: count of visible public posts associated with cats whose status is `needs_help` or `injured`.

Supported periods: `day`, `week`, `month`, `all`.

Tie-breaking is deterministic: score descending, then user ID ascending.

Moderation

Users shall be able to report inappropriate content.

Duplicate open reports from the same reporter for the same target are idempotent and return the existing open report.

Moderators shall be able to:

review reports;
remove content;
suspend users.
10. Cat Grouping
MVP

After uploading a photo, the application creates an unnamed Unknown cat record and links the observation to it automatically. No nearby-cat suggestions or existing/new cat choice are shown.

Future AI

The AI system shall:

detect cats;
compare nearby cats;
calculate similarity;
suggest possible matches.

Final confirmation always belongs to the user.

11. Non-functional Requirements

The system shall:

support Android devices;
be responsive on different screen sizes;
provide API responses under 300 milliseconds for common requests;
store passwords securely;
encrypt communication using HTTPS;
automatically back up production data;
support future scaling to at least 100,000 users.
12. MVP Scope

Included:

Authentication
Interactive map and nearby pet-care places
Cats and observations
Feed
Lost-pet alerts
Adoption and rehoming posts
Likes
Comments
Profiles
Profile settings and account lifecycle controls
Leaderboards
Reports
Moderation
13. Out of Scope

The following features are not included in MVP:

AI recognition
Push notifications
Web application
Multi-city support
Video uploads
Direct messaging
User following
Offline mode
14. Roadmap
Version 1.0 (MVP)
Authentication
Interactive map
Cat observations
Feed
Profiles
Comments
Likes
Moderation
Leaderboards
Version 1.1
Badges
User levels
Hotspots
Additional statistics
Version 1.2
AI cat recognition
Similarity suggestions
Cat movement history
Version 2.0
Web application
Push notifications
Analytics dashboard
Multi-city support
15. Risks

Potential risks include:

Slow community growth.
Duplicate cat entries.
Incorrect GPS locations.
Abuse of the Needs Help status.
Increasing storage costs.
Content moderation workload.
16. Assumptions

This PRD assumes:

Users have access to GPS-enabled Android devices.
Internet connectivity is available during use.
Most users will contribute genuine observations.
The application will initially focus only on Tashkent.
17. Acceptance Criteria

The MVP is considered complete when users can:

create an account;
authenticate successfully;
upload cat observations;
view observations on the map;
browse the feed;
like observations;
comment on observations;
report inappropriate content;
view user profiles;
access leaderboards;
