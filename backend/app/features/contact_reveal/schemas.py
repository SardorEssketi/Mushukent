from __future__ import annotations

from pydantic import BaseModel


class ContactRevealResponse(BaseModel):
    """Owner contact, returned only by the explicit reveal endpoints (never cached)."""

    phone_number: str
    telegram_username: str | None = None
