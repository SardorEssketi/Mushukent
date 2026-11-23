"""Uptime check timer: infrastructure/ops/uptime_check.py.

Alert once after N consecutive failures, recover once, no repeats while down.
"""

from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "infrastructure" / "ops" / "uptime_check.py"

_spec = importlib.util.spec_from_file_location("uptime_check", SCRIPT)
assert _spec and _spec.loader
uc = importlib.util.module_from_spec(_spec)
sys.modules["uptime_check"] = uc
_spec.loader.exec_module(uc)


def _ok(name: str = "site") -> "uc.Result":
    return uc.Result(name, True, "200", 120)


def _bad(name: str = "site", outcome: str = "522") -> "uc.Result":
    return uc.Result(name, False, outcome, 19600)


def _step(state, result, now, sent=True):
    """One timer run with a Telegram that delivers (or not) every message."""
    state, messages = uc.evaluate(state, [result], now, 2)
    if sent:
        for kind, name, _ in messages:
            uc.mark_sent(state, kind, name)
    uc.finish_unsent_recoveries(state)
    return state, messages


def test_single_failure_sends_nothing():
    state, msgs = _step({}, _bad(), 0)
    assert msgs == []
    state, msgs = _step(state, _ok(), 60)
    assert msgs == [] and state["targets"]["site"] == {}


def test_down_once_then_silent_then_recovered_with_duration():
    state, m1 = _step({}, _bad(outcome="525"), 1000)
    state, m2 = _step(state, _bad(outcome="522"), 1060)
    assert [k for k, _, _ in m2] == ["DOWN"]
    assert "DOWN site" in m2[0][2] and "522" in m2[0][2] and "UTC" in m2[0][2]
    for i in range(3):  # still down: no repeats
        state, m = _step(state, _bad(outcome="timeout"), 1120 + 60 * i)
        assert m == []
    state, m3 = _step(state, _ok(), 1000 + 9 * 60)
    assert [k for k, _, _ in m3] == ["RECOVERED"]
    assert "Down for 9 min 0 s" in m3[0][2] and "timeout" in m3[0][2]
    assert state["targets"]["site"] == {}
    state, m4 = _step(state, _ok(), 1000 + 10 * 60)
    assert m4 == []


def test_undelivered_messages_are_retried():
    state, _ = _step({}, _bad(), 0, sent=False)
    state, m = _step(state, _bad(), 60, sent=False)
    assert [k for k, _, _ in m] == ["DOWN"]
    state, m = _step(state, _bad(), 120, sent=True)  # retried, delivered now
    assert [k for k, _, _ in m] == ["DOWN"]
    state, m = _step(state, _ok(), 180, sent=False)
    assert [k for k, _, _ in m] == ["RECOVERED"]
    state, m = _step(state, _ok(), 240, sent=True)  # retried
    assert [k for k, _, _ in m] == ["RECOVERED"]
    state, m = _step(state, _ok(), 300)
    assert m == []


def test_targets_are_independent():
    state, _ = uc.evaluate({}, [_bad("a"), _ok("b")], 0, 2)
    state, msgs = uc.evaluate(state, [_bad("a"), _ok("b")], 60, 2)
    assert [(k, n) for k, n, _ in msgs] == [("DOWN", "a")]


def test_parse_targets_and_defaults():
    cfg = uc.Config.from_env({})
    assert [n for n, _ in cfg.targets] == [
        "mushukistan.uz",
        "www.mushukistan.uz",
        "api.mushukistan.uz",
    ]
    assert cfg.timeout == 15 and cfg.fails_to_alert == 2
    with pytest.raises(ValueError):
        uc.parse_targets("nonsense")


def test_telegram_uses_ops_chat_and_never_raises():
    cfg = uc.Config.from_env(
        {
            "TELEGRAM_BOT_TOKEN": "tok",
            "TELEGRAM_FEEDBACK_CHAT_ID": "1",
            "TELEGRAM_OPS_CHAT_ID": "2",
        }
    )
    seen = []
    assert uc.send_telegram(cfg, "DOWN x", lambda url, body: seen.append(body))
    assert b"chat_id=2" in seen[0]

    def boom(url, body):
        raise OSError("network")

    assert uc.send_telegram(cfg, "DOWN x", boom) is False
    uc.ping_healthcheck(uc.Config.from_env({"HEALTHCHECK_PING_URL": "https://hc.example/x"}), boom)


def test_run_writes_log_and_state(tmp_path, monkeypatch):
    env = {
        "OPS_UPTIME_TARGETS": "t=https://example.invalid/",
        "OPS_UPTIME_STATE": str(tmp_path / "s.json"),
        "OPS_UPTIME_LOG": str(tmp_path / "logs" / "uptime.log"),
    }
    cfg = uc.Config.from_env(env)
    monkeypatch.setattr(uc, "check_all", lambda c: [_bad("t", "dns")])
    uc.run(cfg)
    uc.run(cfg)
    lines = (tmp_path / "logs" / "uptime.log").read_text().splitlines()
    assert len(lines) == 2 and lines[0].split()[1:3] == ["t", "dns"]
    state = json.loads((tmp_path / "s.json").read_text())
    assert state["targets"]["t"]["fails"] == 2
    assert "alerted" not in state["targets"]["t"]  # Telegram not configured: retried next run


def test_fetch_reports_errors_not_exceptions():
    r = uc.fetch("x", "https://127.0.0.1:9/", 2)
    assert not r.ok and r.outcome in {
        "refused",
        "timeout",
        "reset",
        "URLError",
        "OSError",
    }
