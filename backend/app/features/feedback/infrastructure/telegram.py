from __future__ import annotations

from html import escape

import httpx
from structlog import get_logger

from app.features.feedback.domain.models import FeedbackCategory, FeedbackNotification

logger = get_logger(__name__)

TELEGRAM_MESSAGE_LIMIT = 4096
_CATEGORY_LABELS = {
    FeedbackCategory.BUG: "Bug Report",
    FeedbackCategory.SUGGESTION: "Feature Suggestion",
    FeedbackCategory.OTHER: "Other Feedback",
}
_PLATFORM_LABELS = {"web": "Web", "android": "Android"}


def format_feedback_message(notification: FeedbackNotification) -> str:
    """Render a Telegram HTML message. Every user-controlled value is escaped."""
    platform = (
        _PLATFORM_LABELS.get(notification.platform.value, "Unknown")
        if notification.platform
        else "Unknown"
    )
    if notification.app_version:
        platform = f"{platform} {notification.app_version}"
    header = (
        "<b>New Mushukistan Feedback</b>\n\n"
        f"Category: {_CATEGORY_LABELS[notification.category]}\n"
        f"User: {escape(notification.user_label)}\n"
        f"Platform: {escape(platform)}\n"
        f"Date: {notification.created_at.strftime('%Y-%m-%d %H:%M UTC')}\n\n"
        "Message:\n"
    )
    footer = f"\n\nFeedback ID: <code>{notification.feedback_id}</code>"
    wrapper = "<blockquote></blockquote>"
    room = TELEGRAM_MESSAGE_LIMIT - len(header) - len(footer) - len(wrapper)
    body = notification.message
    # Escaping can grow the text, so shrink the raw message until the escaped form fits.
    while body and len(escape(body)) > room:
        body = body[:-1]
    return f"{header}<blockquote>{escape(body)}</blockquote>{footer}"


class TelegramFeedbackNotifier:
    """Best-effort developer notification through the Telegram Bot API.

    Never raises: the feedback is already stored when this runs. The bot token
    is part of the request URL, so failures are logged by exception type only.
    """

    def __init__(
        self,
        *,
        bot_token: str,
        chat_id: str,
        timeout_seconds: float = 5.0,
        client: httpx.Client | None = None,
    ) -> None:
        self._bot_token = bot_token
        self._chat_id = chat_id
        self._timeout = timeout_seconds
        self._client = client

    @property
    def enabled(self) -> bool:
        return bool(self._bot_token and self._chat_id)

    def notify(self, notification: FeedbackNotification) -> bool:
        if not self.enabled:
            logger.info("feedback_telegram_disabled", feedback_id=str(notification.feedback_id))
            return False
        url = f"https://api.telegram.org/bot{self._bot_token}/sendMessage"
        payload = {
            "chat_id": self._chat_id,
            "text": format_feedback_message(notification),
            "parse_mode": "HTML",
            "disable_web_page_preview": True,
        }
        try:
            post = self._client.post if self._client is not None else httpx.post
            response = post(url, json=payload, timeout=self._timeout)
            response.raise_for_status()
        except Exception as exc:  # noqa: BLE001 - a notification must never break submission
            status = getattr(getattr(exc, "response", None), "status_code", None)
            logger.warning(
                "feedback_telegram_failed",
                feedback_id=str(notification.feedback_id),
                error_type=type(exc).__name__,
                status_code=status,
            )
            return False
        logger.info("feedback_telegram_sent", feedback_id=str(notification.feedback_id))
        return True
