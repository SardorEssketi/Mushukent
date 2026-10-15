"""Optional PostHog analytics that can never break the API.

Policy (see docs/SECURITY.md, "Analytics"):
* Analytics are optional. Missing, partial or failing configuration disables analytics and logs a
  warning that names the setting but never its value. It does not stop the API or the tests.
* ``POSTHOG_REQUIRED=true`` is the deliberate fail-fast switch for deployments that want startup
  to fail when analytics cannot be initialised.
* Once running, every analytics call goes through :class:`SafeAnalyticsClient`, so an outage or a
  library error is logged and dropped instead of surfacing in a user request.
"""

from __future__ import annotations

import atexit
import time
from typing import Any

from structlog import get_logger

from app.core.config import Settings
from app.core.posthog_logging import configure_posthog_log_export, shutdown_posthog_log_export

logger = get_logger(__name__)

_FAILURE_LOG_INTERVAL_SECONDS = 60.0


class SafeAnalyticsClient:
    """Proxy that turns any exception from the wrapped PostHog client into a log line."""

    def __init__(self, client: Any) -> None:
        self._client = client
        self._last_failure_log = 0.0

    def __getattr__(self, name: str) -> Any:
        attribute = getattr(self._client, name)
        if not callable(attribute):
            return attribute

        def guarded(*args: Any, **kwargs: Any) -> Any:
            try:
                return attribute(*args, **kwargs)
            except Exception as exc:  # analytics must never affect a request
                self._log_failure(name, exc)
                return None

        return guarded

    def _log_failure(self, operation: str, exc: Exception) -> None:
        now = time.monotonic()
        if now - self._last_failure_log >= _FAILURE_LOG_INTERVAL_SECONDS:
            self._last_failure_log = now
            logger.warning(
                "analytics_call_failed", operation=operation, error_type=type(exc).__name__
            )


class Analytics:
    """Owns the PostHog client and log export for one application lifespan."""

    def __init__(self) -> None:
        self.client: SafeAnalyticsClient | None = None
        self._raw_client: Any = None
        self._log_export_started = False

    def start(self, settings: Settings) -> SafeAnalyticsClient | None:
        token, host = settings.posthog_project_token, settings.posthog_host
        if not (token and host):
            missing = [
                name
                for name, value in (("POSTHOG_PROJECT_TOKEN", token), ("POSTHOG_HOST", host))
                if not value
            ]
            if settings.posthog_required:
                raise RuntimeError(
                    f"POSTHOG_REQUIRED is set but {', '.join(missing)} is missing or empty."
                )
            logger.warning("analytics_disabled", missing_settings=missing)
            return None

        try:
            from posthog import Posthog

            self._raw_client = Posthog(
                project_api_key=token,
                host=host,
                # Automatic exception reports carry stack traces and error messages that can
                # contain personal data. They stay off until sanitisation is demonstrated.
                enable_exception_autocapture=False,
                # Do not let PostHog derive a location from the server's requests.
                disable_geoip=True,
            )
            atexit.register(self._raw_client.shutdown)
            self.client = SafeAnalyticsClient(self._raw_client)
        except Exception as exc:
            self._raw_client = None
            if settings.posthog_required:
                raise RuntimeError("PostHog client could not be initialised.") from exc
            logger.warning("analytics_init_failed", error_type=type(exc).__name__)
            return None

        try:
            export_logger = configure_posthog_log_export(token, host)
            self._log_export_started = True
            export_logger.info("posthog_log_export_started", extra={"component": "api"})
        except Exception as exc:
            # Log export is a bonus on top of event capture; keep events working without it.
            logger.warning("analytics_log_export_failed", error_type=type(exc).__name__)
        return self.client

    def stop(self) -> None:
        if self._log_export_started:
            try:
                shutdown_posthog_log_export()
            except Exception as exc:
                logger.warning("analytics_shutdown_failed", error_type=type(exc).__name__)
            self._log_export_started = False
        if self._raw_client is not None:
            try:
                self._raw_client.flush()
            except Exception as exc:
                logger.warning("analytics_shutdown_failed", error_type=type(exc).__name__)
            # Unregister the exit hook so repeated app lifespans (tests, reloads) do not pile up.
            atexit.unregister(self._raw_client.shutdown)
            try:
                self._raw_client.shutdown()
            except Exception as exc:
                logger.warning("analytics_shutdown_failed", error_type=type(exc).__name__)
            self._raw_client = None
            self.client = None
