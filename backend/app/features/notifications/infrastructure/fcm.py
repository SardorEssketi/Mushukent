from __future__ import annotations

from dataclasses import dataclass

import firebase_admin
from firebase_admin import credentials, exceptions, messaging


@dataclass(frozen=True)
class PushResult:
    success: bool
    invalid_token: bool = False
    error_code: str | None = None


class FcmSender:
    def __init__(self, credentials_file: str, project_id: str) -> None:
        if not credentials_file or not project_id:
            raise ValueError("FCM credentials and project ID are required")
        credential = credentials.Certificate(credentials_file)
        if credential.project_id != project_id:
            raise ValueError("FCM service account project does not match FIREBASE_PROJECT_ID")
        self.app = firebase_admin.initialize_app(
            credential,
            {"projectId": project_id},
            name="mushukistan-notifications",
        )

    def send(self, token: str, title: str, body: str, data: dict[str, str]) -> PushResult:
        try:
            messaging.send(
                messaging.Message(
                    token=token,
                    notification=messaging.Notification(title=title, body=body),
                    data=data,
                    android=messaging.AndroidConfig(priority="normal"),
                ),
                app=self.app,
            )
            return PushResult(success=True)
        except (
            messaging.UnregisteredError,
            messaging.SenderIdMismatchError,
            exceptions.InvalidArgumentError,
        ) as exc:
            return PushResult(success=False, invalid_token=True, error_code=type(exc).__name__)
        except Exception as exc:
            return PushResult(success=False, error_code=type(exc).__name__)
