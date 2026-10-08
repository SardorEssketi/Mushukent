from __future__ import annotations

from datetime import UTC, datetime
from pathlib import Path
from uuid import UUID

from cryptography.fernet import Fernet

from app.core.config import Settings
from app.core.security import api_error
from app.features.notifications.application.schemas import (
    AlertPoint,
    NotificationItem,
    NotificationPage,
    PreferencePatch,
    PreferenceResponse,
)
from app.features.notifications.infrastructure.repository import NotificationRepository
from app.infrastructure.db.session import DatabaseSessionManager


class NotificationService:
    def __init__(self, manager: DatabaseSessionManager, settings: Settings) -> None:
        self.manager = manager
        self.settings = settings

    @property
    def push_available(self) -> bool:
        if not (
            self.settings.firebase_credentials_file
            and self.settings.firebase_project_id
            and Path(self.settings.firebase_credentials_file).is_file()
        ):
            return False
        try:
            Fernet(self.settings.push_token_encryption_key.encode())
        except (ValueError, TypeError):
            return False
        return True

    def _preference_response(
        self, repo: NotificationRepository, user_id: UUID
    ) -> PreferenceResponse:
        preference = repo.preferences(user_id)
        location = repo.get_alert_location(user_id)
        return PreferenceResponse(
            push_comments=preference.push_comments,
            push_replies=preference.push_replies,
            push_followups=preference.push_followups,
            nearby_enabled=preference.nearby_enabled,
            inactivity_enabled=preference.inactivity_enabled,
            alert_location=AlertPoint(latitude=location[0], longitude=location[1])
            if location
            else None,
            push_available=self.push_available,
        )

    def preferences(self, user_id: UUID) -> PreferenceResponse:
        with self.manager.session_scope() as session:
            return self._preference_response(NotificationRepository(session), user_id)

    def update_preferences(self, user_id: UUID, patch: PreferencePatch) -> PreferenceResponse:
        with self.manager.session_scope() as session:
            repo = NotificationRepository(session)
            preference = repo.preferences(user_id)
            if patch.alert_location is not None:
                repo.set_alert_location(
                    preference, patch.alert_location.latitude, patch.alert_location.longitude
                )
                session.flush()
            for field in ("push_comments", "push_replies", "push_followups", "inactivity_enabled"):
                if field in patch.model_fields_set:
                    setattr(preference, field, getattr(patch, field))
            if "nearby_enabled" in patch.model_fields_set:
                preference.nearby_enabled = bool(patch.nearby_enabled)
                if not preference.nearby_enabled:
                    preference.alert_location = None
            if preference.nearby_enabled and repo.get_alert_location(user_id) is None:
                raise api_error(422, "ALERT_LOCATION_REQUIRED", "Save an alert point first.")
            session.flush()
            return self._preference_response(repo, user_id)

    def list_notifications(self, user_id: UUID, limit: int, cursor: str | None) -> NotificationPage:
        with self.manager.session_scope() as session:
            try:
                rows, next_cursor = NotificationRepository(session).list_page(
                    user_id, limit, cursor
                )
            except (ValueError, KeyError, TypeError) as exc:
                raise api_error(422, "INVALID_CURSOR", "Invalid notification cursor.") from exc
            return NotificationPage(
                items=[
                    NotificationItem(
                        id=item.id,
                        kind=item.kind,
                        actor_name=actor_name,
                        target_kind=item.target_kind,
                        target_id=item.target_id,
                        comment_id=item.comment_id,
                        created_at=item.created_at,
                        read_at=item.read_at,
                    )
                    for item, actor_name in rows
                ],
                next_cursor=next_cursor,
                limit=limit,
            )

    def unread_count(self, user_id: UUID) -> int:
        with self.manager.session_scope() as session:
            return NotificationRepository(session).unread_count(user_id)

    def mark_read(self, user_id: UUID, notification_id: UUID) -> None:
        with self.manager.session_scope() as session:
            if not NotificationRepository(session).mark_read(
                user_id, notification_id, datetime.now(UTC)
            ):
                raise api_error(404, "NOTIFICATION_NOT_FOUND", "Notification not found.")

    def mark_all_read(self, user_id: UUID) -> int:
        with self.manager.session_scope() as session:
            return NotificationRepository(session).mark_all_read(user_id, datetime.now(UTC))

    def record_activity(self, user_id: UUID) -> None:
        with self.manager.session_scope() as session:
            NotificationRepository(session).record_activity(user_id, datetime.now(UTC))

    def register_device(self, user_id: UUID, token: str, previous_token: str | None = None) -> None:
        if not self.push_available:
            raise api_error(503, "PUSH_NOT_CONFIGURED", "Android push is not configured.")
        try:
            Fernet(self.settings.push_token_encryption_key.encode())
        except (ValueError, TypeError) as exc:
            raise api_error(503, "PUSH_NOT_CONFIGURED", "Android push key is invalid.") from exc
        with self.manager.session_scope() as session:
            repo = NotificationRepository(session)
            if previous_token and previous_token != token:
                repo.delete_device(user_id, previous_token)
            repo.upsert_device(user_id, token, self.settings.push_token_encryption_key)

    def unregister_device(self, user_id: UUID, token: str) -> None:
        with self.manager.session_scope() as session:
            NotificationRepository(session).delete_device(user_id, token)
