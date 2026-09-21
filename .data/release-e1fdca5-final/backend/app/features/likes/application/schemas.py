from __future__ import annotations

from pydantic import BaseModel, ConfigDict


class LikeResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    liked: bool
    like_count: int
