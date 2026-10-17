"""PostHog must be optional, outage-proof and safe to start and stop repeatedly (audit F-05)."""

from __future__ import annotations

import atexit
import time

import pytest
from fastapi.testclient import TestClient

import app.core.analytics as analytics_module
from app.core.analytics import Analytics, SafeAnalyticsClient
from app.core.config import Settings, get_settings
from app.core.posthog_logging import get_posthog_logger
from app.main import create_app


@pytest.fixture()
def configure(monkeypatch: pytest.MonkeyPatch):
    """Apply PostHog-related environment values and rebuild settings."""

    def apply(**values: str | None) -> Settings:
        for name in ("POSTHOG_PROJECT_TOKEN", "POSTHOG_HOST", "POSTHOG_REQUIRED"):
            monkeypatch.delenv(name, raising=False)
        for name, value in values.items():
            if value is not None:
                monkeypatch.setenv(name, value)
        get_settings.cache_clear()
        return get_settings()

    yield apply
    get_settings.cache_clear()


class FakePosthog:
    instances: list[FakePosthog] = []

    def __init__(self, **kwargs) -> None:
        self.kwargs = kwargs
        self.events: list[tuple] = []
        self.flushed = self.shut_down = 0
        FakePosthog.instances.append(self)

    def capture(self, *args, **kwargs):
        self.events.append((args, kwargs))

    def set(self, **kwargs):
        self.events.append(("set", kwargs))

    def flush(self):
        self.flushed += 1

    def shutdown(self):
        self.shut_down += 1


@pytest.fixture()
def fake_posthog(monkeypatch: pytest.MonkeyPatch):
    FakePosthog.instances = []
    monkeypatch.setattr("posthog.Posthog", FakePosthog)

    class FakeExportLogger:
        def info(self, *args, **kwargs):
            pass

    monkeypatch.setattr(
        analytics_module, "configure_posthog_log_export", lambda *a: FakeExportLogger()
    )
    monkeypatch.setattr(analytics_module, "shutdown_posthog_log_export", lambda: None)
    return FakePosthog


# ------------------------------------------------------------ missing / partial config


def test_missing_analytics_configuration_does_not_stop_the_app(configure) -> None:
    configure()
    with TestClient(create_app()) as client:
        assert client.get("/api/v1/health").status_code == 200
        assert client.app.state.posthog_client is None


@pytest.mark.parametrize(
    "values",
    [
        {"POSTHOG_PROJECT_TOKEN": "phc_token"},
        {"POSTHOG_HOST": "https://eu.i.posthog.com"},
    ],
)
def test_partial_configuration_disables_analytics_without_failing(configure, values) -> None:
    configure(**values)
    with TestClient(create_app()) as client:
        assert client.get("/api/v1/health").status_code == 200
        assert client.app.state.posthog_client is None


def test_required_flag_makes_missing_configuration_fail_fast(configure) -> None:
    configure(POSTHOG_REQUIRED="true")
    with pytest.raises(RuntimeError, match="POSTHOG_REQUIRED"):
        with TestClient(create_app()):
            pass


def test_required_flag_names_the_missing_setting_but_not_secret_values(configure) -> None:
    configure(POSTHOG_REQUIRED="true", POSTHOG_PROJECT_TOKEN="phc_super_secret_token")
    with pytest.raises(RuntimeError) as error:
        with TestClient(create_app()):
            pass
    assert "POSTHOG_HOST" in str(error.value)
    assert "phc_super_secret_token" not in str(error.value)


def test_disabled_warning_never_contains_secrets(configure, capsys) -> None:
    configure(POSTHOG_PROJECT_TOKEN="phc_super_secret_token")
    with TestClient(create_app()):
        pass
    captured = capsys.readouterr()
    assert "phc_super_secret_token" not in captured.out + captured.err


# ----------------------------------------------------------------- unavailable PostHog


def test_unreachable_posthog_host_does_not_break_requests_or_shutdown(configure) -> None:
    configure(POSTHOG_PROJECT_TOKEN="phc_unreachable", POSTHOG_HOST="http://127.0.0.1:9")
    started = time.monotonic()
    with TestClient(create_app()) as client:
        assert client.get("/api/v1/health").status_code == 200
        assert client.app.state.posthog_client is not None
        client.app.state.posthog_client.capture("outage_probe")
        assert client.get("/api/v1/health").status_code == 200
    assert time.monotonic() - started < 30  # bounded flush: an outage cannot hang shutdown
    assert get_posthog_logger() is None  # export state is reset after shutdown


def test_client_init_failure_disables_analytics_unless_required(
    configure, monkeypatch, capsys
) -> None:
    class Boom:
        def __init__(self, **kwargs):
            raise ValueError("secret-in-message")

    monkeypatch.setattr("posthog.Posthog", Boom)
    configure(POSTHOG_PROJECT_TOKEN="phc_token", POSTHOG_HOST="https://eu.i.posthog.com")
    with TestClient(create_app()) as client:
        assert client.get("/api/v1/health").status_code == 200
        assert client.app.state.posthog_client is None
    assert "secret-in-message" not in capsys.readouterr().out  # only the error type is logged

    configure(
        POSTHOG_PROJECT_TOKEN="phc_token",
        POSTHOG_HOST="https://eu.i.posthog.com",
        POSTHOG_REQUIRED="true",
    )
    with pytest.raises(RuntimeError, match="could not be initialised"):
        with TestClient(create_app()):
            pass


def test_log_export_failure_keeps_event_capture_working(
    configure, fake_posthog, monkeypatch
) -> None:
    def broken(*args):
        raise OSError("exporter unavailable")

    monkeypatch.setattr(analytics_module, "configure_posthog_log_export", broken)
    configure(POSTHOG_PROJECT_TOKEN="phc_token", POSTHOG_HOST="https://eu.i.posthog.com")
    with TestClient(create_app()) as client:
        assert client.app.state.posthog_client is not None
        client.app.state.posthog_client.capture("still_works")
        assert fake_posthog.instances[-1].events


# --------------------------------------------------------------- correct configuration


def test_correctly_configured_analytics_collects_events(configure, fake_posthog) -> None:
    configure(POSTHOG_PROJECT_TOKEN="phc_token", POSTHOG_HOST="https://eu.i.posthog.com")
    with TestClient(create_app()) as client:
        assert client.get("/api/v1/health").status_code == 200
        client.app.state.posthog_client.capture("post_created", properties={"photo_count": 1})
    (instance,) = fake_posthog.instances
    assert instance.kwargs["project_api_key"] == "phc_token"
    assert instance.kwargs["host"] == "https://eu.i.posthog.com"
    assert instance.events == [(("post_created",), {"properties": {"photo_count": 1}})]
    assert instance.flushed == 1 and instance.shut_down == 1


# --------------------------------------------------------------------- failure isolation


def test_analytics_errors_never_reach_the_caller(caplog) -> None:
    class Exploding:
        value = 7

        def capture(self, *args, **kwargs):
            raise ConnectionError("posthog is down")

    client = SafeAnalyticsClient(Exploding())
    assert client.capture("event", properties={"a": 1}) is None  # swallowed, not raised
    assert client.value == 7  # non-callable attributes pass through
    for _ in range(100):
        client.capture("event")  # repeated failures stay quiet and cheap


def test_failure_logging_is_rate_limited(monkeypatch) -> None:
    logged: list[str] = []
    monkeypatch.setattr(
        analytics_module.logger, "warning", lambda event, **kw: logged.append(event)
    )

    class Exploding:
        def capture(self, *args, **kwargs):
            raise RuntimeError("down")

    client = SafeAnalyticsClient(Exploding())
    for _ in range(500):
        client.capture("event")
    assert logged == ["analytics_call_failed"]


def test_a_failing_analytics_context_does_not_fail_the_request(
    configure, fake_posthog, monkeypatch
) -> None:
    def broken_context():
        raise RuntimeError("context unavailable")

    monkeypatch.setattr("app.main.new_context", broken_context)
    configure(POSTHOG_PROJECT_TOKEN="phc_token", POSTHOG_HOST="https://eu.i.posthog.com")
    with TestClient(create_app()) as client:
        assert client.get("/api/v1/health").status_code == 200


def test_application_errors_are_not_swallowed_by_the_analytics_layer(
    configure, fake_posthog
) -> None:
    configure(POSTHOG_PROJECT_TOKEN="phc_token", POSTHOG_HOST="https://eu.i.posthog.com")
    application = create_app()

    @application.get("/boom")
    def boom():
        raise ZeroDivisionError("application bug")

    with TestClient(application, raise_server_exceptions=False) as client:
        assert client.get("/boom").status_code == 500


# -------------------------------------------------- lifecycle: no leaks, no repeat init


def test_repeated_lifecycles_register_and_release_exit_hooks_symmetrically(
    configure, fake_posthog, monkeypatch
) -> None:
    registered: list[object] = []
    unregistered: list[object] = []
    monkeypatch.setattr(atexit, "register", lambda fn, *a, **k: registered.append(fn) or fn)
    monkeypatch.setattr(atexit, "unregister", lambda fn: unregistered.append(fn))
    settings = configure(POSTHOG_PROJECT_TOKEN="phc_token", POSTHOG_HOST="https://eu.i.posthog.com")
    for _ in range(5):
        analytics = Analytics()
        assert analytics.start(settings) is not None
        analytics.stop()
        analytics.stop()  # stopping twice is safe
    assert len(registered) == len(unregistered) == 5
    assert len(fake_posthog.instances) == 5  # exactly one client per lifecycle
    assert all(i.shut_down == 1 for i in fake_posthog.instances)


def test_stop_tolerates_failures_during_flush_and_shutdown(configure, fake_posthog) -> None:
    settings = configure(POSTHOG_PROJECT_TOKEN="phc_token", POSTHOG_HOST="https://eu.i.posthog.com")
    analytics = Analytics()
    analytics.start(settings)

    def explode():
        raise OSError("network down")

    fake_posthog.instances[-1].flush = explode
    fake_posthog.instances[-1].shutdown = explode
    analytics.stop()  # must not raise


def test_stop_without_start_is_a_no_op() -> None:
    Analytics().stop()
