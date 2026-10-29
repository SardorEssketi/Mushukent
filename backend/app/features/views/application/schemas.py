from __future__ import annotations

from pydantic import BaseModel


class PostViewResponse(BaseModel):
    view_count: int
    counted: bool
