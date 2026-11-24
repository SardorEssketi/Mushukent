"""Only this platform's own media URLs leave the API.

A user-controlled image URL on another host makes every viewer's client load it from a third
party: the viewer's IP address leaks to that host and the image skips our upload checks. Rows
written before this rule (for example an avatar set through the old PATCH field) may still hold
such URLs, so responses filter them instead of migrating data.
"""

from __future__ import annotations

from typing import Annotated

from pydantic import AfterValidator

from app.core.storage import ObjectStorage
from app.infrastructure.storage.service import media_key_for_url

_storage: ObjectStorage | None = None


def configure_public_media_storage(storage: ObjectStorage | None) -> None:
    """Set the storage whose URLs count as ours (called once when the app is built)."""
    global _storage
    _storage = storage


def public_media_url(url: str | None) -> str | None:
    """``url`` when it points at our media storage, otherwise None.

    Fails closed: with no storage configured nothing counts as ours.
    """
    storage = _storage
    if not url or storage is None:
        return None
    return url if media_key_for_url(storage, url) is not None else None


# Response field type for user-supplied image URLs such as avatars.
PublicMediaUrl = Annotated[str | None, AfterValidator(public_media_url)]
