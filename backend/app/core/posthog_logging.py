"""Isolated OpenTelemetry log export for PostHog-authored log lines only."""

import logging
from typing import Any

POSTHOG_LOGGER_NAME = "mushukistan.posthog"

_logger: logging.Logger | None = None
_logger_provider: Any = None


def configure_posthog_log_export(project_token: str, host: str) -> logging.Logger:
    """Configure the dedicated logger without affecting existing app log handlers."""
    global _logger, _logger_provider

    if _logger is not None:
        return _logger

    # OpenTelemetry logs remain under private imports while the API is experimental.
    from opentelemetry._logs import set_logger_provider
    from opentelemetry.exporter.otlp.proto.http._log_exporter import OTLPLogExporter
    from opentelemetry.sdk._logs import LoggerProvider, LoggingHandler
    from opentelemetry.sdk._logs.export import BatchLogRecordProcessor

    logger_provider = LoggerProvider()
    set_logger_provider(logger_provider)
    logger_provider.add_log_record_processor(
        BatchLogRecordProcessor(
            OTLPLogExporter(
                endpoint=f"{host.rstrip('/')}/i/v1/logs",
                headers={"Authorization": f"Bearer {project_token}"},
                timeout=5,
            )
        )
    )

    logger = logging.getLogger(POSTHOG_LOGGER_NAME)
    logger.setLevel(logging.INFO)
    logger.propagate = False
    logger.addHandler(LoggingHandler(logger_provider=logger_provider))

    _logger = logger
    _logger_provider = logger_provider
    return logger


def get_posthog_logger() -> logging.Logger | None:
    """Return the exporter logger only after PostHog log export is configured."""
    return _logger


def shutdown_posthog_log_export() -> None:
    """Flush and stop only the provider created for the dedicated PostHog logger.

    The flush is bounded so an unreachable PostHog host cannot hold up application shutdown, and
    the module state is reset so a later start (tests, reloads) configures a fresh exporter.
    """
    global _logger, _logger_provider

    provider, logger = _logger_provider, _logger
    _logger = None
    _logger_provider = None
    if logger is not None:
        for handler in list(logger.handlers):
            logger.removeHandler(handler)
    if provider is not None:
        try:
            provider.force_flush(timeout_millis=3000)
        finally:
            provider.shutdown()
