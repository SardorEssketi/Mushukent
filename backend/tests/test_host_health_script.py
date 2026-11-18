"""Host health timer (LT-20 step 2): infrastructure/ops/host_health.py and the Nginx ops log."""

from __future__ import annotations

import importlib.util
import json
import re
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "infrastructure" / "ops" / "host_health.py"
NGINX_CONF = REPO_ROOT / "infrastructure" / "nginx" / "default.conf"

_spec = importlib.util.spec_from_file_location("host_health", SCRIPT)
assert _spec and _spec.loader
hh = importlib.util.module_from_spec(_spec)
sys.modules["host_health"] = hh
_spec.loader.exec_module(hh)


def _json_line(status: int, route: str = "feed", rt: float = 0.120) -> str:
    return json.dumps(
        {
            "t": "2026-11-18T01:00:00+00:00",
            "host": "api.example",
            "route": route,
            "method": "GET",
            "status": status,
            "rt": rt,
            "urt": "0.118",
            "ust": str(status),
            "bytes": 10,
        }
    )


class FakeDocker:
    """Answers the four read-only docker commands the script uses; records every call."""

    def __init__(self) -> None:
        self.logs: list[str] = []
        self.containers: list[dict] = []
        self.oom: list[str] = []
        self.calls: list[list[str]] = []
        self.fail = False

    def container(
        self,
        name: str,
        *,
        cid: str = "a",
        restarts: int = 0,
        status: str = "running",
        health: str | None = "healthy",
        oom: bool = False,
        exit_code: int = 0,
    ) -> None:
        state: dict = {"Status": status, "OOMKilled": oom, "ExitCode": exit_code}
        if health:
            state["Health"] = {"Status": health}
        self.containers = [c for c in self.containers if c["Name"] != f"/{name}"]
        self.containers.append(
            {"Name": f"/{name}", "Id": cid, "RestartCount": restarts, "State": state}
        )

    def __call__(self, args: list[str]) -> str:
        self.calls.append(args)
        if self.fail:
            raise hh.subprocess.CalledProcessError(1, ["docker", *args])
        if args[0] == "logs":
            return "\n".join(self.logs)
        if args[0] == "ps":
            return "\n".join(c["Name"].lstrip("/") for c in self.containers)
        if args[0] == "inspect":
            return json.dumps(self.containers)
        if args[0] == "events":
            return "\n".join(
                json.dumps(
                    {"Type": "container", "Action": "oom", "Actor": {"Attributes": {"name": n}}}
                )
                for n in self.oom
            )
        raise AssertionError(f"unexpected docker command {args}")


@pytest.fixture
def cfg(tmp_path: Path):
    return hh.Config(
        state_path=str(tmp_path / "state.json"),
        telegram_token="SECRET-TOKEN",
        telegram_chat_id="42",
        posthog_token="phc",
        posthog_host="https://ph.example",
    )


def _run(cfg, docker: FakeDocker, now: float):
    sent: list[str] = []
    events: list[dict] = []
    props, _ = hh.run_once(
        cfg,
        run=docker,
        now=now,
        telegram=lambda c, text: sent.append(text) or True,
        posthog=lambda c, p, t: events.append(p) or True,
    )
    return props, sent, events


def test_parses_json_and_default_format_lines() -> None:
    lines = [
        _json_line(200, rt=0.100),
        _json_line(502, rt=30.0),
        _json_line(504, rt=30.0),
        _json_line(500),
        _json_line(200, route="web"),
        _json_line(200, route="health"),
        '203.0.113.9 - - [18/Nov/2026:01:00:00 +0000] "GET /api/v1/feed?x=1 HTTP/1.1" 502 0 "-" "u"',  # noqa: E501
        '203.0.113.9 - - [18/Nov/2026:01:00:00 +0000] "GET / HTTP/1.1" 200 10 "-" "ua"',
        "2026/11/18 01:00:00 [error] 29#29: *1 upstream timed out (110: Connection timed out)",
        "{broken json",
        "",
    ]
    minute = hh.parse_nginx_lines(lines)
    assert minute.requests == 8
    assert minute.api_requests == 5  # 4 JSON API lines + the default-format /api/ line
    assert minute.status_502 == 2 and minute.status_504 == 1 and minute.status_5xx_other == 1
    assert minute.gateway_errors == 3
    assert minute.unparsed == 1
    assert sorted(minute.api_times_ms) == [100.0, 120.0, 30000.0, 30000.0]


def test_one_run_sends_one_event_and_only_reads_from_docker(cfg) -> None:
    docker = FakeDocker()
    docker.logs = [_json_line(200, rt=0.2)] * 9 + [_json_line(200, rt=1.0)]
    docker.container("mushukistan-backend")
    docker.container("mushukistan-nginx")
    props, sent, events = _run(cfg, docker, now=10_000.0)

    assert events == [props]
    assert props["requests"] == 10 and props["api_requests"] == 10
    assert props["api_p95_ms"] == 1000.0 and props["api_p50_ms"] == 200.0
    assert props["containers"] == 2 and props["docker_ok"] is True
    assert sent == []  # first run: baseline only
    assert {call[0] for call in docker.calls} == {"logs", "ps", "inspect", "events"}
    ps = next(call for call in docker.calls if call[0] == "ps")
    assert "label=com.docker.compose.oneoff=False" in ps  # migrations (compose run) left out


def test_log_window_continues_from_the_last_run_and_is_capped(cfg) -> None:
    docker = FakeDocker()
    _run(cfg, docker, now=10_000.0)
    _run(cfg, docker, now=10_060.0)
    since = [call[call.index("--since") + 1] for call in docker.calls if call[0] == "logs"]
    assert since == ["9940.000", "10000.000"]
    _run(cfg, docker, now=20_000.0)  # after a long gap: at most 10 minutes back
    assert [c for c in docker.calls if c[0] == "logs"][-1][2] == "19400.000"


def test_gateway_errors_fire_repeat_and_resolve(cfg) -> None:
    docker = FakeDocker()
    docker.container("mushukistan-nginx")
    docker.logs = [_json_line(504)] * 3
    _, sent, _ = _run(cfg, docker, now=1_000.0)
    assert sent == []  # 3 < 5
    _, sent, _ = _run(cfg, docker, now=1_060.0)
    assert len(sent) == 1 and sent[0].startswith("🔴 CRITICAL") and "6 Nginx 502/504" in sent[0]
    docker.logs = []
    _, sent, _ = _run(cfg, docker, now=1_120.0)
    assert sent == []  # still 6 in the window, already reported
    _, sent, _ = _run(cfg, docker, now=1_000.0 + 30 * 60 + 60)
    # the errors have left the 10-minute window
    assert len(sent) == 1 and sent[0].startswith("✅ RESOLVED") and "nginx_502_504" in sent[0]


def test_still_critical_is_repeated_every_30_minutes(cfg) -> None:
    docker = FakeDocker()
    docker.container("mushukistan-backend", status="exited", health=None)
    t = 5_000.0
    _, sent, _ = _run(cfg, docker, now=t)
    assert sent == []  # one run down is tolerated (deploy swap)
    _, sent, _ = _run(cfg, docker, now=t + 60)
    assert len(sent) == 1 and "mushukistan-backend is exited" in sent[0]
    _, sent, _ = _run(cfg, docker, now=t + 60 + 29 * 60)
    assert sent == []
    _, sent, _ = _run(cfg, docker, now=t + 60 + 30 * 60)
    assert len(sent) == 1 and sent[0].startswith("🔴 STILL CRITICAL (30 min)")
    docker.container("mushukistan-backend")
    _, sent, _ = _run(cfg, docker, now=t + 60 + 31 * 60)
    assert len(sent) == 1 and sent[0].startswith("✅ RESOLVED")


def test_restart_and_oom_are_critical_but_a_recreate_is_only_a_notice(cfg) -> None:
    docker = FakeDocker()
    docker.container("mushukistan-backend", cid="one", restarts=0)
    docker.container("mushukistan-db", cid="db", restarts=0)
    _run(cfg, docker, now=1_000.0)

    docker.container("mushukistan-backend", cid="one", restarts=1, exit_code=137, oom=True)
    docker.oom = ["mushukistan-backend"]
    props, sent, _ = _run(cfg, docker, now=1_060.0)
    assert props["restarts"] == 1 and props["oom_kills"] == 1
    assert any("restarted (1x; exit code 137, OOMKilled=true)" in s for s in sent)
    assert any("out-of-memory kill" in s for s in sent)
    assert all(s.startswith("🔴 CRITICAL") for s in sent)

    docker.oom = []
    docker.container("mushukistan-backend", cid="two", restarts=0)  # recreated by a deploy
    props, sent, _ = _run(cfg, docker, now=1_120.0)
    assert props["restarts"] == 0
    assert sent == [
        "ℹ️ Mushukistan production host\nmushukistan-backend was recreated "
        "(a deploy or a manual change)"
    ]


def test_docker_failure_is_reported_after_two_runs_and_keeps_the_baseline(cfg) -> None:
    docker = FakeDocker()
    docker.container("mushukistan-backend", cid="one")
    _run(cfg, docker, now=1_000.0)
    docker.fail = True
    props, sent, _ = _run(cfg, docker, now=1_060.0)
    assert props["docker_ok"] is False and sent == []
    _, sent, _ = _run(cfg, docker, now=1_120.0)
    assert len(sent) == 1 and "Docker did not answer" in sent[0]
    docker.fail = False
    _, sent, _ = _run(cfg, docker, now=1_180.0)
    assert len(sent) == 1 and sent[0].startswith("✅ RESOLVED")  # no false "recreated" notice


def test_dry_run_sends_nothing_and_keeps_no_state(cfg, capsys) -> None:
    docker = FakeDocker()
    docker.logs = [_json_line(502)] * 10
    sent: list[str] = []
    hh.run_once(
        cfg,
        run=docker,
        now=1_000.0,
        dry_run=True,
        telegram=lambda c, t: sent.append(t) or True,
        posthog=lambda c, p, t: sent.append("posthog") or True,
    )
    assert sent == []
    assert not Path(cfg.state_path).exists()
    out = capsys.readouterr().out
    assert '"status_502": 10' in out and "CRITICAL" in out
    assert '"gateway_errors": 10' in out


def test_senders_never_raise_and_never_print_the_token(cfg, capsys) -> None:
    def broken(url: str, data: bytes, content_type: str) -> None:
        raise OSError(f"connection refused for {url}")

    assert hh.send_telegram(cfg, "hello", post=broken) is False
    assert hh.send_posthog(cfg, {"a": 1}, 0.0, post=broken) is False
    err = capsys.readouterr().err
    assert "SECRET-TOKEN" not in err and "phc" not in err and "OSError" in err

    seen: list[tuple[str, bytes]] = []
    hh.send_posthog(cfg, {"a": 1}, 0.0, post=lambda u, d, c: seen.append((u, d)))
    url, body = seen[0]
    payload = json.loads(body)
    assert url == "https://ph.example/i/v0/e/"
    assert payload["event"] == "host_health_minute"
    assert payload["distinct_id"] == "mushukistan-host"
    assert payload["properties"]["$process_person_profile"] is False


def test_without_credentials_nothing_is_sent() -> None:
    bare = hh.Config()
    assert hh.send_telegram(bare, "x", post=lambda *a: pytest.fail("sent")) is False
    assert hh.send_posthog(bare, {}, 0.0, post=lambda *a: pytest.fail("sent")) is False


def test_chat_falls_back_to_the_feedback_chat_like_the_backend() -> None:
    cfg = hh.Config.from_env({"TELEGRAM_BOT_TOKEN": "t", "TELEGRAM_FEEDBACK_CHAT_ID": "7"})
    assert cfg.telegram_chat_id == "7"
    cfg = hh.Config.from_env(
        {"TELEGRAM_OPS_CHAT_ID": "9", "TELEGRAM_FEEDBACK_CHAT_ID": "7", "POSTHOG_HOST": "h/"}
    )
    assert cfg.telegram_chat_id == "9" and cfg.posthog_host == "h"


def test_nginx_ops_log_is_on_every_server_and_carries_no_personal_data() -> None:
    conf = NGINX_CONF.read_text(encoding="utf-8")
    fmt = re.search(r"log_format ops_json escape=json(.*?);\n", conf, re.S)
    assert fmt, "ops_json log format missing"
    for forbidden in (
        "$remote_addr",
        "$http_user_agent",
        "$request_uri",
        "$args",
        "$http_x_forwarded_for",
        "$http_cf_connecting_ip",
        "$http_authorization",
        "$uri",
        "$request ",
    ):
        assert forbidden not in fmt.group(1)
    for needed in (
        "$status",
        "$request_time",
        "$upstream_response_time",
        "$upstream_status",
        "$ops_route",
    ):
        assert needed in fmt.group(1)
    servers = conf.count("\nserver {")
    assert servers == 3
    assert conf.count("access_log /var/log/nginx/access.log ops_json;") == servers


def test_systemd_units_point_at_the_installed_script() -> None:
    ops = REPO_ROOT / "infrastructure" / "ops"
    service = (ops / "mushukistan-host-health.service.example").read_text(encoding="utf-8")
    timer = (ops / "mushukistan-host-health.timer.example").read_text(encoding="utf-8")
    assert "ExecStart=/usr/bin/python3 /usr/local/lib/mushukistan-ops/host_health.py" in service
    assert "EnvironmentFile=/etc/mushukistan-ops/host-health.env" in service
    assert "ReadWritePaths=/var/lib/mushukistan-ops" in service
    assert "OnCalendar=*-*-* *:*:00" in timer


def test_telegram_install_check_sends_one_message(monkeypatch, capsys) -> None:
    sent: list[str] = []
    monkeypatch.setenv("TELEGRAM_BOT_TOKEN", "t")
    monkeypatch.setenv("TELEGRAM_OPS_CHAT_ID", "9")
    monkeypatch.setattr(hh, "send_telegram", lambda cfg, text: sent.append(text) or True)
    assert hh.main(["--test-telegram"]) == 0
    assert len(sent) == 1 and "test message" in sent[0]
    monkeypatch.setattr(hh, "send_telegram", lambda cfg, text: False)
    assert hh.main(["--test-telegram"]) == 1
    assert "NOT sent" in capsys.readouterr().out
