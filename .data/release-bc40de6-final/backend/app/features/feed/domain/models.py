from __future__ import annotations

from enum import StrEnum


class FeedFilter(StrEnum):
    RECENT = "recent"
    POPULAR = "popular"
    NEARBY = "nearby"
    INJURED = "injured"
    NEEDS_HELP = "needs_help"
    ADOPTION = "adoption"


class FeedPopularPeriod(StrEnum):
    DAY = "day"
    MONTH = "month"
    ALL = "all"
