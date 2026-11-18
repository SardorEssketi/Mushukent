"""Notification worker graceful stop: SIGTERM ends the loop within seconds (no database needed)."""

from __future__ import annotations

import os
import signal
import sys
import threading
import time

import pytest
from cryptography.fernet import Fernet

from app.core.config import Settings
from app.features.notifications.application import worker as worker_module
from app.features.notifications.application.worker import NotificationWorker


class _Manager:
    """Never touched: drain and the schedulers are replaced in these tests."""


def _worker(monkeypatch) -> NotificationWorker:
    w = NotificationWorker(
        _Manager(), Settings(push_token_encryption_key=Fernet.generate_key().decode()), None
    )
    monkeypatch.setattr(w, "enqueue_due_followups", lambda now: 0)
    monkeypatch.setattr(w, "enqueue_inactivity", lambda now: 0)
    return w


def test_stop_interrupts_the_poll_wait(monkeypatch) -> None:
    w = _worker(monkeypatch)
    passes: list[int] = []
    monkeypatch.setattr(w, "drain", lambda now: passes.append(1) or 0)
    thread = threading.Thread(target=w.run_forever)
    thread.start()
    time.sleep(0.2)  # now waiting out the 30 s poll interval
    started = time.monotonic()
    w.request_stop()
    thread.join(5)
    assert not thread.is_alive()
    assert time.monotonic() - started < 2
    assert passes == [1]
    assert worker_module.POLL_SECONDS >= 30  # the wait it cut short


def test_a_stop_before_the_next_pass_runs_nothing(monkeypatch) -> None:
    w = _worker(monkeypatch)
    monkeypatch.setattr(w, "drain", lambda now: pytest.fail("drained after stop"))
    w.request_stop()
    w.run_forever()  # returns at once


@pytest.mark.skipif(sys.platform == "win32", reason="POSIX signals")
def test_sigterm_stops_the_worker(monkeypatch) -> None:
    w = _worker(monkeypatch)
    monkeypatch.setattr(w, "drain", lambda now: 0)
    previous = signal.getsignal(signal.SIGTERM)
    try:
        w.install_signal_handlers()
        threading.Timer(0.3, os.kill, (os.getpid(), signal.SIGTERM)).start()
        started = time.monotonic()
        w.run_forever()  # main thread: the handler runs here and sets the stop event
        assert time.monotonic() - started < 3
        assert w.stop_event.is_set()
    finally:
        signal.signal(signal.SIGTERM, previous)
