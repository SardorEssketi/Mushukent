from __future__ import annotations

from typing import Protocol
from uuid import UUID

from app.features.lost_pets.domain.models import LostPetCreateDraft, LostPetPage, LostPetRecord


class LostPetRepository(Protocol):
    def create(self, draft: LostPetCreateDraft) -> LostPetRecord: ...

    def get_by_id(self, lost_pet_id: UUID) -> LostPetRecord | None: ...

    def list_public(
        self,
        *,
        limit: int,
        cursor: str | None = None,
        latitude: float | None = None,
        longitude: float | None = None,
        radius_meters: int | None = None,
        valid_for_map: bool = False,
    ) -> LostPetPage: ...
