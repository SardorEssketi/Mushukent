#!/usr/bin/env python3
"""Mushukistan host health check (LT-20 step 2). Runs once a minute from a systemd timer.

What the backend cannot see by itself:
- Nginx 502/504 (the backend never answered), counted from Nginx's JSON access log.
- Container restarts, OOM kills, containers not running or unhealthy, from the Docker API.

Each run sends one PostHog event, ``host_health_minute``, and evaluates the critical rules. A rule
that starts firing sends "CRITICAL" to the ops Telegram chat (the same bot and chat as the
backend's alerts), "STILL CRITICAL" every ``OPS_HOST_REPEAT_MINUTES`` while it fires, and
"RESOLVED" when it clears. One-off events (restart, OOM kill) send a single CRITICAL.

Read-only towards the containers: it runs ``docker logs``, ``docker events``, ``docker ps`` and
``docker inspect`` only. It writes one state file. Python standard library only. Secrets come from
the environment (systemd ``EnvironmentFile``) and are never printed.

Usage: host_health.py [--dry-run | --test-telegram]
  --dry-run: print the event and the alerts; send nothing; keep no state.
  --test-telegram: send one test message to the ops chat and exit (install check).
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import time
import urllib.parse
import urllib.request
from collections.abc import Callable, Iterable
from dataclasses import dataclass, field
from typing import Any

STATE_VERSION = 1
OPS_PREFIX = "🚨 OPS · "
MAX_LOOKBACK_S = 600  # after downtime, look back at most 10 minutes
GATEWAY_STATUSES = (502, 504)
# Fallback for Nginx's default "combined" format: addr - user [time] "request" status bytes ...
_COMBINED = re.compile(
    r'^\S+ \S+ \S+ \[[^\]]+\] "(?:[A-Z]+ (\S+)[^"]*|[^"]*)" (\d{3}) '
)


@dataclass(frozen=True)
class Config:
    compose_project: str = "mushukistan"
    nginx_container: str = "mushukistan-nginx"
    label: str = "Mushukistan production host"
    state_path: str = "/var/lib/mushukistan-ops/host-health.json"
    telegram_token: str = ""
    telegram_chat_id: str = ""
    posthog_token: str = ""
    posthog_host: str = ""
    gateway_errors_10m: int = 5
    window_minutes: int = 10
    down_runs: int = (
        2  # consecutive runs before "not running / unhealthy" fires (deploy swaps)
    )
    repeat_minutes: int = 30
    resolve_after_runs: int = (
        5  # one run a minute: RESOLVED after 5 clear minutes in a row
    )

    @classmethod
    def from_env(cls, env: dict[str, str]) -> Config:
        def num(name: str, default: int) -> int:
            raw = env.get(name, "").strip()
            return int(raw) if raw else default

        return cls(
            compose_project=env.get("OPS_COMPOSE_PROJECT") or cls.compose_project,
            nginx_container=env.get("OPS_NGINX_CONTAINER") or cls.nginx_container,
            label=env.get("OPS_HOST_LABEL") or cls.label,
            state_path=env.get("OPS_STATE_PATH") or cls.state_path,
            telegram_token=env.get("TELEGRAM_BOT_TOKEN", "").strip(),
            telegram_chat_id=(
                env.get("TELEGRAM_OPS_CHAT_ID", "").strip()
                or env.get("TELEGRAM_FEEDBACK_CHAT_ID", "").strip()
            ),
            posthog_token=env.get("POSTHOG_PROJECT_TOKEN", "").strip(),
            posthog_host=env.get("POSTHOG_HOST", "").strip().rstrip("/"),
            gateway_errors_10m=num(
                "OPS_HOST_GATEWAY_ERRORS_10M", cls.gateway_errors_10m
            ),
            repeat_minutes=num("OPS_HOST_REPEAT_MINUTES", cls.repeat_minutes),
        )


# -- Nginx log ------------------------------------------------------------------------------------


@dataclass
class NginxMinute:
    requests: int = 0
    api_requests: int = 0
    status_502: int = 0
    status_504: int = 0
    status_5xx_other: int = 0
    unparsed: int = 0
    api_times_ms: list[float] = field(default_factory=list)

    @property
    def gateway_errors(self) -> int:
        return self.status_502 + self.status_504


def parse_nginx_lines(lines: Iterable[str]) -> NginxMinute:
    """Counts access-log lines. JSON (``ops_json``) first; the default format as a fallback, so the
    timer also works before the Nginx log format change is deployed. Error-log lines are ignored.
    """
    out = NginxMinute()
    for line in lines:
        line = line.strip()
        if not line:
            continue
        status: int | None = None
        route = ""
        rt: float | None = None
        if line.startswith("{"):
            try:
                record = json.loads(line)
                status = int(record["status"])
                route = str(record.get("route", ""))
                rt = float(record["rt"])
            except (ValueError, KeyError, TypeError):
                out.unparsed += 1
                continue
        else:
            match = _COMBINED.match(line)
            if not match:
                continue  # not an access-log line (Nginx notices, errors)
            status = int(match.group(2))
            route = "api_other" if (match.group(1) or "").startswith("/api/") else ""
        out.requests += 1
        is_api = route not in ("", "web", "media", "health")
        if is_api:
            out.api_requests += 1
            if rt is not None:
                out.api_times_ms.append(rt * 1000.0)
        if status == 502:
            out.status_502 += 1
        elif status == 504:
            out.status_504 += 1
        elif status >= 500:
            out.status_5xx_other += 1
    return out


def percentile(values: list[float], q: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, int(q * len(ordered)))]


# -- Docker ---------------------------------------------------------------------------------------

Runner = Callable[[list[str]], str]


def run_docker(args: list[str]) -> str:
    done = subprocess.run(
        ["docker", *args], capture_output=True, text=True, timeout=20, check=True
    )
    return done.stdout + done.stderr  # Nginx writes access to stdout, errors to stderr


@dataclass
class ContainerState:
    name: str
    id: str
    status: str
    health: str
    restarts: int
    oom_killed: bool
    exit_code: int


def read_containers(run: Runner, project: str) -> list[ContainerState]:
    # Services only: one-off `docker compose run` containers (migrations) are left out.
    names = run(
        [
            "ps",
            "-a",
            "--filter",
            f"label=com.docker.compose.project={project}",
            "--filter",
            "label=com.docker.compose.oneoff=False",
            "--format",
            "{{.Names}}",
        ]
    ).split()
    if not names:
        return []
    raw = json.loads(run(["inspect", *names]))
    out = []
    for item in raw:
        state = item.get("State", {})
        out.append(
            ContainerState(
                name=item.get("Name", "").lstrip("/"),
                id=item.get("Id", ""),
                status=state.get("Status", "unknown"),
                health=(state.get("Health") or {}).get("Status", "none"),
                restarts=int(item.get("RestartCount", 0)),
                oom_killed=bool(state.get("OOMKilled", False)),
                exit_code=int(state.get("ExitCode", 0)),
            )
        )
    return out


def read_oom_events(run: Runner, project: str, since: float, until: float) -> list[str]:
    """Container names with an ``oom`` event in the window."""
    text = run(
        [
            "events",
            "--since",
            f"{since:.3f}",
            "--until",
            f"{until:.3f}",
            "--filter",
            "type=container",
            "--filter",
            "event=oom",
            "--filter",
            f"label=com.docker.compose.project={project}",
            "--format",
            "{{json .}}",
        ]
    )
    names = []
    for line in text.splitlines():
        try:
            names.append(json.loads(line)["Actor"]["Attributes"]["name"])
        except (ValueError, KeyError, TypeError):
            continue
    return names


# -- Alerts ---------------------------------------------------------------------------------------


@dataclass
class Findings:
    sustained: dict[str, str]  # rule -> description, while firing
    events: list[tuple[str, str]]  # (cooldown key, message): one-off critical events
    notices: list[str]  # informational messages
    restarts: int = 0


def evaluate(
    cfg: Config,
    state: dict[str, Any],
    nginx: NginxMinute,
    containers: list[ContainerState],
    oom_names: list[str],
    now: float,
) -> Findings:
    sustained: dict[str, str] = {}
    events: list[str] = []
    notices: list[str] = []

    history = [
        h for h in state.get("gateway", []) if h["t"] > now - cfg.window_minutes * 60
    ]
    history.append({"t": now, "n": nginx.gateway_errors})
    state["gateway"] = history
    gateway = sum(h["n"] for h in history)
    if gateway >= cfg.gateway_errors_10m:
        sustained["nginx_502_504"] = (
            f"{gateway} Nginx 502/504 in the last {cfg.window_minutes} min "
            f"(limit {cfg.gateway_errors_10m})"
        )

    previous = state.get("containers", {})
    down_counts = state.get("down", {})
    seen: dict[str, Any] = {}
    restarts = 0
    for c in containers:
        before = previous.get(c.name)
        if before and before["id"] == c.id and c.restarts > before["restarts"]:
            restarts += c.restarts - before["restarts"]
            events.append(
                (
                    f"restart:{c.name}",
                    f"{c.name} restarted ({c.restarts - before['restarts']}x; "
                    f"exit code {c.exit_code}, OOMKilled={str(c.oom_killed).lower()})",
                )
            )
        elif before and before["id"] != c.id:
            notices.append(f"{c.name} was recreated (a deploy or a manual change)")
        seen[c.name] = {"id": c.id, "restarts": c.restarts}

        bad = c.status != "running" or c.health == "unhealthy"
        down_counts[c.name] = down_counts.get(c.name, 0) + 1 if bad else 0
        if down_counts[c.name] >= cfg.down_runs:
            sustained[f"container_{c.name}"] = (
                f"{c.name} is {c.status} (health: {c.health})"
            )
    for name in set(previous) - set(seen):
        notices.append(f"{name} is gone (removed)")
    state["containers"] = seen
    state["down"] = {k: v for k, v in down_counts.items() if k in seen}

    for name in sorted(set(oom_names)):
        events.append((f"oom:{name}", f"{name}: out-of-memory kill (Docker oom event)"))
    return Findings(
        sustained=sustained, events=events, notices=notices, restarts=restarts
    )


def alert_messages(
    cfg: Config, state: dict[str, Any], findings: Findings, now: float
) -> list[str]:
    """CRITICAL / STILL CRITICAL / RESOLVED transitions, plus one-off events and notices.

    Anti-spam: a one-off event (restart, OOM) of the same container is sent at most once per
    `repeat_minutes`, with the number suppressed since; a sustained rule is RESOLVED only after
    `resolve_after_runs` clear runs in a row (a re-fire in between continues the incident); all
    notices of one run share one message.
    """
    label = cfg.label
    messages: list[str] = []
    cooldown = state.get("cooldown", {})
    for key, text in findings.events:
        info = cooldown.get(key)
        if info is not None and now - info["sent"] < cfg.repeat_minutes * 60:
            info["suppressed"] += 1
            continue
        more = info["suppressed"] if info else 0
        extra = f" (+{more} more since the last alert)" if more else ""
        messages.append(f"🔴 CRITICAL · {label}\n{text}{extra}")
        cooldown[key] = {"sent": now, "suppressed": 0}
    state["cooldown"] = {
        k: v
        for k, v in cooldown.items()
        if now - v["sent"] < 24 * 3600 or v["suppressed"]
    }
    if findings.notices:
        messages.append(f"ℹ️ {label}\n" + "\n".join(findings.notices))
    active = state.get("alerts", {})
    clear = state.get("clear", {})
    for rule, text in findings.sustained.items():
        clear.pop(rule, None)
        info = active.get(rule)
        if info is None:
            messages.append(f"🔴 CRITICAL · {label}\n{text}")
            active[rule] = {"since": now, "sent": now}
        elif now - info["sent"] >= cfg.repeat_minutes * 60:
            minutes = round((now - info["since"]) / 60)
            messages.append(f"🔴 STILL CRITICAL ({minutes} min) · {label}\n{text}")
            info["sent"] = now
    for rule in [r for r in active if r not in findings.sustained]:
        clear[rule] = clear.get(rule, 0) + 1
        if clear[rule] >= cfg.resolve_after_runs:
            minutes = round((now - active.pop(rule)["since"]) / 60)
            del clear[rule]
            messages.append(f"✅ RESOLVED after {minutes} min · {label}\n{rule}")
    state["alerts"], state["clear"] = active, clear
    return messages


# -- Senders --------------------------------------------------------------------------------------


def _post(url: str, data: bytes, content_type: str) -> None:
    request = urllib.request.Request(
        url, data=data, headers={"Content-Type": content_type}
    )
    with urllib.request.urlopen(
        request, timeout=10
    ) as response:  # noqa: S310 (fixed https URLs)
        response.read()


def send_telegram(
    cfg: Config, text: str, post: Callable[[str, bytes, str], None] = _post
) -> bool:
    if not (cfg.telegram_token and cfg.telegram_chat_id):
        return False
    url = f"https://api.telegram.org/bot{cfg.telegram_token}/sendMessage"
    # Same prefix as the backend's ops alerts: feedback and ops share the owner's DM.
    text = OPS_PREFIX + text
    body = urllib.parse.urlencode(
        {"chat_id": cfg.telegram_chat_id, "text": text}
    ).encode()
    try:
        post(url, body, "application/x-www-form-urlencoded")
        return True
    except (
        Exception
    ) as error:  # never let a send failure stop the check; never print the URL
        print(f"telegram send failed: {type(error).__name__}", file=sys.stderr)
        return False


def send_posthog(
    cfg: Config,
    properties: dict[str, Any],
    now: float,
    post: Callable[[str, bytes, str], None] = _post,
) -> bool:
    if not (cfg.posthog_token and cfg.posthog_host):
        return False
    payload = {
        "api_key": cfg.posthog_token,
        "event": "host_health_minute",
        "distinct_id": "mushukistan-host",
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now)),
        "properties": {**properties, "$process_person_profile": False},
    }
    try:
        post(
            f"{cfg.posthog_host}/i/v0/e/",
            json.dumps(payload).encode(),
            "application/json",
        )
        return True
    except Exception as error:
        print(f"posthog send failed: {type(error).__name__}", file=sys.stderr)
        return False


# -- One run --------------------------------------------------------------------------------------


def load_state(path: str) -> dict[str, Any]:
    try:
        with open(path, encoding="utf-8") as handle:
            state = json.load(handle)
        return (
            state
            if state.get("version") == STATE_VERSION
            else {"version": STATE_VERSION}
        )
    except (OSError, ValueError):
        return {"version": STATE_VERSION}


def save_state(path: str, state: dict[str, Any]) -> None:
    tmp = f"{path}.tmp"
    with open(tmp, "w", encoding="utf-8") as handle:
        json.dump(state, handle)
    os.replace(tmp, path)


def run_once(
    cfg: Config,
    *,
    run: Runner = run_docker,
    now: float | None = None,
    dry_run: bool = False,
    telegram: Callable[[Config, str], bool] = send_telegram,
    posthog: Callable[[Config, dict[str, Any], float], bool] = send_posthog,
) -> tuple[dict[str, Any], list[str]]:
    now = time.time() if now is None else now
    state = load_state(cfg.state_path)
    since = max(float(state.get("until", now - 60)), now - MAX_LOOKBACK_S)
    docker_ok = True
    try:
        logs = run(
            [
                "logs",
                "--since",
                f"{since:.3f}",
                "--until",
                f"{now:.3f}",
                cfg.nginx_container,
            ]
        )
        nginx = parse_nginx_lines(logs.splitlines())
        containers = read_containers(run, cfg.compose_project)
        oom = read_oom_events(run, cfg.compose_project, since, now)
    except (subprocess.SubprocessError, OSError, ValueError) as error:
        print(f"docker query failed: {type(error).__name__}", file=sys.stderr)
        docker_ok, nginx, containers, oom = False, NginxMinute(), [], []

    if docker_ok:
        findings = evaluate(cfg, state, nginx, containers, oom, now)
    else:  # keep the container baseline; report the check itself as failing
        failures = state.get("docker_failures", 0) + 1
        state["docker_failures"] = failures
        sustained = (
            {"docker": "Docker did not answer the health check"}
            if failures >= 2
            else {}
        )
        findings = Findings(sustained=sustained, events=[], notices=[])
    if docker_ok:
        state["docker_failures"] = 0

    properties = {
        "window_s": round(now - since, 1),
        "requests": nginx.requests,
        "api_requests": nginx.api_requests,
        "status_502": nginx.status_502,
        "status_504": nginx.status_504,
        "status_5xx_other": nginx.status_5xx_other,
        "gateway_errors": nginx.gateway_errors,  # 502 + 504, one series for PostHog
        "api_p50_ms": _round(percentile(nginx.api_times_ms, 0.50)),
        "api_p95_ms": _round(percentile(nginx.api_times_ms, 0.95)),
        "unparsed_lines": nginx.unparsed,
        "containers": len(containers),
        "containers_not_running": sum(c.status != "running" for c in containers),
        "containers_unhealthy": sum(c.health == "unhealthy" for c in containers),
        "restarts": findings.restarts,
        "oom_kills": len(set(oom)),
        "docker_ok": docker_ok,
        "alerts_firing": len(findings.sustained),
    }
    messages = alert_messages(cfg, state, findings, now)
    state["until"] = now
    if dry_run:
        print(
            json.dumps(
                {"event": "host_health_minute", "properties": properties}, indent=2
            )
        )
        for message in messages:
            print("---\n" + message)
        return properties, messages
    posthog(cfg, properties, now)
    for message in messages:
        telegram(cfg, message)
    save_state(cfg.state_path, state)
    print(
        f"host_health requests={nginx.requests} 502={nginx.status_502} 504={nginx.status_504} "
        f"api_p95_ms={properties['api_p95_ms']} containers={len(containers)} "
        f"alerts={len(findings.sustained)} messages={len(messages)}"
    )
    return properties, messages


def _round(value: float | None) -> float | None:
    return None if value is None else round(value, 1)


def main(argv: list[str]) -> int:
    cfg = Config.from_env(dict(os.environ))
    if "--test-telegram" in argv:
        sent = send_telegram(
            cfg, f"ℹ️ {cfg.label}\nHost health check installed (test message)."
        )
        print(
            "telegram test: sent"
            if sent
            else "telegram test: NOT sent (token, chat or network)"
        )
        return 0 if sent else 1
    run_once(cfg, dry_run="--dry-run" in argv)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
