from __future__ import annotations

from enum import StrEnum


class CatStatus(StrEnum):
    HEALTHY = "healthy"
    INJURED = "injured"
    NEEDS_HELP = "needs_help"
    ADOPTED = "adopted"
    UNKNOWN = "unknown"
    FEED = "feed"


class ReportTargetType(StrEnum):
    POST = "post"
    COMMENT = "comment"
    USER = "user"
    CAT = "cat"
    LOST_PET = "lost_pet"
    ADOPTION_POST = "adoption_post"


class ReportStatus(StrEnum):
    OPEN = "open"
    RESOLVED = "resolved"
    DISMISSED = "dismissed"


class LeaderboardType(StrEnum):
    MOST_ACTIVE = "most_active"
    MOST_POPULAR = "most_popular"
    TOP_HELPERS = "top_helpers"


class PlaceCategory(StrEnum):
    PET_SHOP = "pet_shop"
    VETERINARY = "veterinary"
    SHELTER = "shelter"


class PlaceSource(StrEnum):
    OSM = "osm"
    MANUAL = "manual"
