#!/usr/bin/env python3
"""Mushukistan uptime check. Runs once a minute from a systemd timer on the production host.

Requests the public URLs (the web hosts through Cloudflare, the API directly) and expects HTTP 200
without following redirects. A target that fails on ``OPS_UPTIME_FAILS_TO_ALERT`` consecutive runs
(default 2) sends one "DOWN" message to the ops Telegram chat (the same bot, chat and prefix as
host_health.py). It sends nothing more while it stays down. The first success after that sends one
"RECOVERED" message with the downtime, counted from the first failed check. A failure shorter than
the threshold sends nothing. A message that fails to send is retried on the next run.

Every check is appended to ``OPS_UPTIME_LOG`` (one line: UTC time, target, code or error, ms),
rotated by logrotate. After every run the script pings ``HEALTHCHECK_PING_URL`` when it is set: an
external dead-man's switch (healthchecks.io) that alerts when the pings stop, i.e. when this host,
its network or the timer is down, which this script cannot report by itself.

Python standard library only. Secrets come from the environment (systemd ``EnvironmentFile``) and
are never printed.

Usage: uptime_check.py [--dry-run | --test-telegram]
  --dry-run: check the targets and print the results and the messages; send nothing, write nothing.
  --test-telegram: send one test message to the ops chat and exit (install check).

Environment (all optional except the Telegram values):
  TELEGRAM_BOT_TOKEN, TELEGRAM_OPS_CHAT_ID (falls back to TELEGRAM_FEEDBACK_CHAT_ID)
  OPS_UPTIME_TARGETS   comma-separated name=url (default: the three production URLs below)
  OPS_UPTIME_TIMEOUT   seconds per request (default 15)
  OPS_UPTIME_FAILS_TO_ALERT  consecutive failures before DOWN (default 2)
  OPS_UPTIME_STATE     state file (default /var/lib/mushukistan-ops/uptime.json)
  OPS_UPTIME_LOG       check log (default /var/log/mushukistan-ops/uptime.log)
  OPS_UPTIME_LABEL     prefix for the message text, e.g. "[TEST] " for a test run
  HEALTHCHECK_PING_URL dead-man's-switch ping URL (unset: no ping)
"""

from __future__ import annotations

import json
import os
import socket
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from datetime import datetime, timezone

OPS_PREFIX = "🚨 OPS · "
RECOVERED_PREFIX = "✅ OPS · "
STATE_VERSION = 1
USER_AGENT = "mushukistan-uptime/1"
DEFAULT_TARGETS = (
    "mushukistan.uz=https://mushukistan.uz/,"
    "www.mushukistan.uz=https://www.mushukistan.uz/,"
    "api.mushukistan.uz=https://api.mushukistan.uz/health"
)


@dataclass(frozen=True)
class Config:
    targets: tuple[tuple[str, str], ...]
    timeout: float = 15.0
    fails_to_alert: int = 2
    state_path: str = "/var/lib/mushukistan-ops/uptime.json"
    log_path: str = "/var/log/mushukistan-ops/uptime.log"
    label: str = ""
    telegram_token: str = ""
    telegram_chat_id: str = ""
    ping_url: str = ""

    @classmethod
    def from_env(cls, env: dict[str, str]) -> "Config":
        return cls(
            targets=parse_targets(env.get("OPS_UPTIME_TARGETS") or DEFAULT_TARGETS),
            timeout=float(env.get("OPS_UPTIME_TIMEOUT") or cls.timeout),
            fails_to_alert=max(
                1, int(env.get("OPS_UPTIME_FAILS_TO_ALERT") or cls.fails_to_alert)
            ),
            state_path=env.get("OPS_UPTIME_STATE") or cls.state_path,
            log_path=env.get("OPS_UPTIME_LOG") or cls.log_path,
            label=env.get("OPS_UPTIME_LABEL", ""),
            telegram_token=env.get("TELEGRAM_BOT_TOKEN", "").strip(),
            telegram_chat_id=(
                env.get("TELEGRAM_OPS_CHAT_ID", "").strip()
                or env.get("TELEGRAM_FEEDBACK_CHAT_ID", "").strip()
            ),
            ping_url=env.get("HEALTHCHECK_PING_URL", "").strip(),
        )


def parse_targets(raw: str) -> tuple[tuple[str, str], ...]:
    targets = []
    for item in raw.split(","):
        name, sep, url = item.strip().partition("=")
        if (
            not sep
            or not name.strip()
            or not url.strip().startswith(("http://", "https://"))
        ):
            raise ValueError(f"bad OPS_UPTIME_TARGETS entry: {item.strip()!r}")
        targets.append((name.strip(), url.strip()))
    if not targets:
        raise ValueError("OPS_UPTIME_TARGETS is empty")
    return tuple(targets)


@dataclass(frozen=True)
class Result:
    name: str
    ok: bool
    outcome: (
        str  # HTTP status code ("200", "522") or an error word ("timeout", "tls", ...)
    )
    ms: int


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(
        self, *args, **kwargs
    ):  # a redirect is reported as its own status
        return None


_OPENER = urllib.request.build_opener(_NoRedirect)


def _error_word(error: BaseException) -> str:
    reason = getattr(error, "reason", error)
    if isinstance(reason, (socket.timeout, TimeoutError)) or "timed out" in str(reason):
        return "timeout"
    if isinstance(reason, ssl.SSLError):
        return "tls"
    if isinstance(reason, socket.gaierror):
        return "dns"
    if isinstance(reason, ConnectionRefusedError):
        return "refused"
    if isinstance(reason, (ConnectionResetError, ConnectionAbortedError)):
        return "reset"
    return type(reason).__name__


def fetch(name: str, url: str, timeout: float) -> Result:
    request = urllib.request.Request(
        url, headers={"User-Agent": USER_AGENT, "Cache-Control": "no-cache"}
    )
    start = time.monotonic()
    try:
        with _OPENER.open(
            request, timeout=timeout
        ) as response:  # noqa: S310 (configured https URLs)
            response.read(65536)
            code = response.status
    except urllib.error.HTTPError as error:
        code = error.code
    except (
        Exception
    ) as error:  # every network failure becomes an outcome, never a crash
        return Result(
            name, False, _error_word(error), int((time.monotonic() - start) * 1000)
        )
    return Result(name, code == 200, str(code), int((time.monotonic() - start) * 1000))


def utc(ts: float) -> str:
    return datetime.fromtimestamp(ts, timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")


def duration(seconds: float) -> str:
    seconds = max(0, int(round(seconds)))
    hours, rest = divmod(seconds, 3600)
    minutes, secs = divmod(rest, 60)
    if hours:
        return f"{hours} h {minutes} min"
    if minutes:
        return f"{minutes} min {secs} s"
    return f"{secs} s"


def evaluate(
    state: dict, results: list[Result], now: float, fails_to_alert: int
) -> tuple[dict, list[tuple[str, str, str]]]:
    """Return the new per-target state and the messages as (kind, target, text).

    The state of a message is committed by ``mark_sent`` only after it was delivered.
    """
    targets = dict(state.get("targets", {}))
    messages: list[tuple[str, str, str]] = []
    for r in results:
        t = dict(targets.get(r.name, {}))
        if r.ok:
            if t.get("alerted"):
                down_for = now - t.get("first_fail", now)
                messages.append(
                    (
                        "RECOVERED",
                        r.name,
                        f"RECOVERED {r.name}\nHTTP {r.outcome} at {utc(now)}\n"
                        f"Down for {duration(down_for)} (since {utc(t.get('first_fail', now))}; "
                        f"last error: {t.get('last_error', '?')})",
                    )
                )
                t["recovering"] = (
                    True  # cleared by mark_sent once the message is delivered
                )
            else:
                t = {}
        else:
            if t.get(
                "recovering"
            ):  # failed again before RECOVERED was delivered: still down
                t.pop("recovering")
            t.setdefault("first_fail", now)
            t["fails"] = t.get("fails", 0) + 1
            t["last_error"] = r.outcome
            if t["fails"] >= fails_to_alert and not t.get("alerted"):
                messages.append(
                    (
                        "DOWN",
                        r.name,
                        f"DOWN {r.name}\n{r.outcome} on {t['fails']} checks in a row\n"
                        f"First failure {utc(t['first_fail'])}, now {utc(now)}",
                    )
                )
        targets[r.name] = t
    # Targets that are no longer configured are forgotten.
    names = {r.name for r in results}
    return {
        "version": STATE_VERSION,
        "targets": {k: v for k, v in targets.items() if k in names},
    }, messages


def mark_sent(state: dict, kind: str, name: str) -> None:
    t = state["targets"].get(name, {})
    if kind == "DOWN":
        t["alerted"] = True
    elif kind == "RECOVERED":
        state["targets"][name] = {}


def finish_unsent_recoveries(state: dict) -> None:
    """A RECOVERED that was not delivered keeps the target 'alerted' so the next run retries it."""
    for t in state["targets"].values():
        t.pop("recovering", None)


def _post(url: str, data: bytes | None, timeout: float = 10) -> None:
    request = urllib.request.Request(url, data=data, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(
        request, timeout=timeout
    ) as response:  # noqa: S310 (fixed https URLs)
        response.read()


def send_telegram(
    cfg: Config, text: str, post: Callable[[str, bytes | None], None] = _post
) -> bool:
    if not (cfg.telegram_token and cfg.telegram_chat_id):
        print("telegram not configured", file=sys.stderr)
        return False
    url = f"https://api.telegram.org/bot{cfg.telegram_token}/sendMessage"
    prefix = RECOVERED_PREFIX if text.startswith("RECOVERED") else OPS_PREFIX
    body = urllib.parse.urlencode(
        {"chat_id": cfg.telegram_chat_id, "text": prefix + cfg.label + text}
    ).encode()
    try:
        post(url, body)
        return True
    except (
        Exception
    ) as error:  # never let a send failure stop the check; never print the URL
        print(f"telegram send failed: {type(error).__name__}", file=sys.stderr)
        return False


def ping_healthcheck(
    cfg: Config, post: Callable[[str, bytes | None], None] = _post
) -> None:
    if not cfg.ping_url:
        return
    try:
        post(cfg.ping_url, None)
    except Exception as error:  # never print the URL: it is a secret
        print(f"heartbeat ping failed: {type(error).__name__}", file=sys.stderr)


def load_state(path: str) -> dict:
    try:
        with open(path, encoding="utf-8") as fh:
            state = json.load(fh)
        if state.get("version") == STATE_VERSION and isinstance(
            state.get("targets"), dict
        ):
            return state
    except (OSError, ValueError):
        pass
    return {"version": STATE_VERSION, "targets": {}}


def save_state(path: str, state: dict) -> None:
    tmp = f"{path}.tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(state, fh)
    os.replace(tmp, path)


def log_lines(results: list[Result], now: float) -> list[str]:
    stamp = datetime.fromtimestamp(now, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    return [
        f"{stamp} {r.name} {r.outcome} {r.ms}ms {'ok' if r.ok else 'FAIL'}\n"
        for r in results
    ]


def check_all(
    cfg: Config, fetcher: Callable[[str, str, float], Result] = fetch
) -> list[Result]:
    with ThreadPoolExecutor(max_workers=len(cfg.targets)) as pool:
        return list(pool.map(lambda t: fetcher(t[0], t[1], cfg.timeout), cfg.targets))


def run(cfg: Config, dry_run: bool = False) -> int:
    now = time.time()
    results = check_all(cfg)
    state, messages = evaluate(
        load_state(cfg.state_path), results, now, cfg.fails_to_alert
    )
    if dry_run:
        for line in log_lines(results, now):
            print(line, end="")
        for kind, _, text in messages:
            print(f"--- would send {kind}:\n{text}")
        return 0
    os.makedirs(os.path.dirname(cfg.log_path) or ".", exist_ok=True)
    with open(cfg.log_path, "a", encoding="utf-8") as fh:
        fh.writelines(log_lines(results, now))
    for kind, name, text in messages:
        if send_telegram(cfg, text):
            mark_sent(state, kind, name)
    finish_unsent_recoveries(state)
    save_state(cfg.state_path, state)
    ping_healthcheck(cfg)
    failed = [r for r in results if not r.ok]
    print(
        f"uptime checks={len(results)} failed={len(failed)} alerts={len(messages)}"
        + "".join(f" {r.name}={r.outcome}" for r in failed)
    )
    return 0


def main(argv: list[str]) -> int:
    cfg = Config.from_env(dict(os.environ))
    if "--test-telegram" in argv:
        ok = send_telegram(
            cfg,
            f"uptime check test message from the production host, {utc(time.time())}",
        )
        print("telegram test sent" if ok else "telegram test FAILED")
        return 0 if ok else 1
    return run(cfg, dry_run="--dry-run" in argv)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
