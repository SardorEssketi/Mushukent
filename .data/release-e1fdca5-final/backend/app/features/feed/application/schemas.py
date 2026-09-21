from __future__ import annotations

from pydantic import BaseModel, ConfigDict, Field, model_validator

from app.features.adoption_posts.application.schemas import AdoptionPostListItem
from app.features.feed.domain.models import FeedFilter, FeedPopularPeriod
from app.features.lost_pets.application.schemas import LostPetListItem
from app.features.posts.application.schemas import PostListItem

FeedListItem = PostListItem | LostPetListItem | AdoptionPostListItem


class FeedQuery(BaseModel):
    model_config = ConfigDict(extra="forbid")

    filter_by: FeedFilter = Field(default=FeedFilter.RECENT, alias="filter")
    popular_period: FeedPopularPeriod = FeedPopularPeriod.ALL
    latitude: float | None = Field(default=None, ge=-90, le=90, alias="lat")
    longitude: float | None = Field(default=None, ge=-180, le=180, alias="lon")
    radius_meters: int | None = Field(default=None, ge=1, le=5000)
    limit: int = Field(default=20, ge=1, le=100)
    cursor: str | None = None

    @model_validator(mode="after")
    def _validate_geo(self) -> "FeedQuery":
        if self.filter_by == FeedFilter.NEARBY:
            if self.latitude is None or self.longitude is None or self.radius_meters is None:
                raise ValueError("Nearby feed requires latitude, longitude and radius_meters.")
        return self
