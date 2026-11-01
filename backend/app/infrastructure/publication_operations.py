"""Short operation transactions; never hold a connection during image processing or R2 IO."""

import json
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from hashlib import sha256
from uuid import UUID, uuid4

from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert

from app.core.security import api_error
from app.infrastructure.db.models.schema import PublicationOperation
from app.infrastructure.db.session import DatabaseSessionManager

LEASE = timedelta(minutes=15)


def publication_fingerprint(kind: str, payload: BaseModel, photos: list) -> str:
    digest = sha256(
        json.dumps(
            [kind, payload.model_dump(mode="json")], sort_keys=True, separators=(",", ":")
        ).encode()
    )
    for content, content_type, _filename in photos:
        digest.update(json.dumps([len(content), content_type]).encode())
        digest.update(sha256(content).digest())
    return digest.hexdigest()


@dataclass
class PublicationContext:
    manager: DatabaseSessionManager
    user_id: UUID
    key: UUID
    target_id: UUID
    owner_token: UUID

    def lock_for_commit(self, session):
        operation = session.scalar(
            select(PublicationOperation)
            .where(
                PublicationOperation.user_id == self.user_id,
                PublicationOperation.key == self.key,
            )
            .with_for_update()
        )
        if (
            operation is None
            or operation.owner_token != self.owner_token
            or operation.state != "pending"
        ):
            raise api_error(
                409,
                "PUBLICATION_IN_PROGRESS",
                "Another attempt owns this publication. Check its status.",
            )
        return operation

    def complete(self, session):
        self.lock_for_commit(session).state = "completed"

    def track_key(self, key: str):
        with self.manager.session_scope() as session:
            operation = self.lock_for_commit(session)
            # Record the intended key before PUT; a lost storage acknowledgement remains auditable.
            operation.media_keys = [
                *operation.media_keys,
                {"key": key, "attempt": str(self.owner_token)},
            ]

    def fail(self):
        with self.manager.session_scope() as session:
            operation = self.lock_for_commit(session)
            operation.state = "failed"


class PublicationOperations:
    def __init__(self, manager: DatabaseSessionManager):
        self.manager = manager

    def status(self, user_id: UUID, key: UUID) -> dict:
        with self.manager.session_scope() as session:
            operation = session.get(PublicationOperation, (user_id, key))
            if operation is None:
                raise api_error(
                    404, "PUBLICATION_OPERATION_NOT_FOUND", "Publication operation not found."
                )
            return {
                "state": operation.state,
                "can_retry": operation.state == "failed"
                or (
                    operation.state == "pending" and operation.lease_expires_at <= datetime.now(UTC)
                ),
                "target_kind": operation.target_kind,
                "target_id": str(operation.target_id),
                "retry_after_seconds": (
                    max(1, int((operation.lease_expires_at - datetime.now(UTC)).total_seconds()))
                    if operation.state == "pending"
                    else 0
                ),
            }

    def reserve(self, user_id: UUID, key: UUID, kind: str, fingerprint: str):
        now = datetime.now(UTC)
        token, target_id = uuid4(), uuid4()
        with self.manager.session_scope() as session:
            session.execute(
                insert(PublicationOperation)
                .values(
                    user_id=user_id,
                    key=key,
                    target_kind=kind,
                    fingerprint=fingerprint,
                    target_id=target_id,
                    owner_token=token,
                    state="pending",
                    lease_expires_at=now + LEASE,
                    media_keys=[],
                )
                .on_conflict_do_nothing()
            )
            operation = session.scalar(
                select(PublicationOperation)
                .where(
                    PublicationOperation.user_id == user_id,
                    PublicationOperation.key == key,
                )
                .with_for_update()
            )
            if operation.target_kind != kind or operation.fingerprint != fingerprint:
                raise api_error(
                    409,
                    "PUBLICATION_KEY_CONFLICT",
                    "This publication key belongs to different content.",
                )
            if operation.state == "completed":
                return operation.target_id
            if (
                operation.owner_token != token
                and operation.state == "pending"
                and operation.lease_expires_at > now
            ):
                raise api_error(
                    409,
                    "PUBLICATION_IN_PROGRESS",
                    "Publication is still processing. Check its status.",
                )
            operation.owner_token = token
            operation.state = "pending"
            operation.lease_expires_at = now + LEASE
            return PublicationContext(self.manager, user_id, key, operation.target_id, token)
