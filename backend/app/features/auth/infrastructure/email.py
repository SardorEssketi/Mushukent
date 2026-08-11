from __future__ import annotations

import json
from urllib import error, request

from app.core.config import Settings
from app.core.security import api_error

RESEND_EMAILS_API_URL = "https://api.resend.com/emails"
RESEND_USER_AGENT = "mushukistan-backend/1.0"


class EmailVerificationSender:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings

    def send_verification_email(self, *, email: str, token: str) -> None:
        if self.settings.app_env.casefold() == "development":
            return
        if (
            not self.settings.resend_api_key
            or not self.settings.resend_from_email
            or not self.settings.public_app_base_url
        ):
            raise api_error(
                500,
                "EMAIL_NOT_CONFIGURED",
                "Email verification is not configured.",
            )

        verify_url = f"{self.settings.public_app_base_url.rstrip('/')}/verify-email?token={token}"
        text = (
            "Confirm your Mushukistan account by opening this link:\n\n"
            f"{verify_url}\n\n"
            "If you did not create this account, ignore this email."
        )
        payload = {
            "from": self.settings.resend_from_email,
            "to": [email],
            "subject": "Verify your Mushukistan account",
            "text": text,
        }
        data = json.dumps(payload).encode("utf-8")
        resend_request = request.Request(
            RESEND_EMAILS_API_URL,
            data=data,
            headers={
                "Authorization": f"Bearer {self.settings.resend_api_key}",
                "Content-Type": "application/json",
                "User-Agent": RESEND_USER_AGENT,
            },
            method="POST",
        )

        try:
            with request.urlopen(resend_request, timeout=10) as response:
                if response.status >= 400:
                    raise api_error(
                        502,
                        "EMAIL_DELIVERY_FAILED",
                        "Email verification could not be sent.",
                    )
        except error.HTTPError as exc:
            raise api_error(
                502,
                "EMAIL_DELIVERY_FAILED",
                "Email verification could not be sent.",
            ) from exc
        except error.URLError as exc:
            raise api_error(
                502,
                "EMAIL_DELIVERY_FAILED",
                "Email verification could not be sent.",
            ) from exc
