from __future__ import annotations

from dataclasses import dataclass


@dataclass(slots=True)
class LikeResult:
    liked: bool
    like_count: int
