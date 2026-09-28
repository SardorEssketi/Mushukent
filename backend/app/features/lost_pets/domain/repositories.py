from __future__ import annotations

from datetime import datetime
from typing import Protocol
from uuid import UUID

from app.features.lost_pets.domain.models import (
    LostPetCreateDraft,
    LostPetFollowUpRecord,
    LostPetMapPage,
    LostPetPage,
    LostPetRecord,
)


class LostPetRepository(Protocol):
    def create(self, draft: LostPetCreateDraft) -> LostPetRecord: ...

    def get_by_id(self, lost_pet_id: UUID) -> LostPetRecord | None: ...

    def get_by_ids(
        self, lost_pet_ids: list[UUID], *, active_only: bool = False
    ) -> list[LostPetRecord]: ...

    def record_contact(self, lost_pet_id: UUID, contacting_user_id: UUID) -> bool: ...

    def list_due_follow_ups(self, owner_id: UUID, now: datetime) -> list[LostPetFollowUpRecord]: ...

    def answer_follow_up(
        self, follow_up_id: UUID, owner_id: UUID, answer_yes: bool, now: datetime
    ) -> tuple[str, UUID | None]: ...

    def list_owned(
        self, owner_id: UUID, *, limit: int, cursor: str | None = None
    ) -> LostPetPage: ...

    def list_public(
        self,
        *,
        limit: int,
        cursor: str | None = None,
        latitude: float | None = None,
        longitude: float | None = None,
        radius_meters: int | None = None,
        valid_for_map: bool = False,
        bbox: tuple[float, float, float, float] | None = None,
    ) -> LostPetPage: ...

    def list_map_markers(
        self,
        *,
        limit: int,
        bbox: tuple[float, float, float, float],
    ) -> LostPetMapPage: ...
