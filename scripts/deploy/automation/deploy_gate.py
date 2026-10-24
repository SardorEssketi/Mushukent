#!/usr/bin/python3 -I
"""SSH forced command for the restricted `mushukistan-deploy` account.

Installed root-owned as /usr/local/lib/mushukistan-deploy/deploy-gate and referenced by
`ForceCommand` (sshd) and `command=` (authorized_keys). Whatever the client asks for
arrives in SSH_ORIGINAL_COMMAND; this program accepts only the fixed verbs below, with
arguments matched against strict patterns (no quoting, no shell), and then execs the
root broker through a single sudo rule. It never starts a shell.
"""
from __future__ import annotations

import os
import re
import sys

BROKER = "/usr/local/lib/mushukistan-deploy/broker"
SUDO = "/usr/bin/sudo"

TOKEN_RE = re.compile(r"^[A-Za-z0-9._-]{1,80}$")
APPROVAL_ID = re.compile(r"^[0-9a-f]{32}$")
RELEASE = re.compile(r"^[0-9]{8}-[0-9a-f]{7}-[A-Za-z0-9._-]{1,40}$")
COUNT = re.compile(r"^[0-9]{1,3}$")
ORIGIN = re.compile(r"^[0-9A-Fa-f:.]{2,45}$")

# verb -> argument patterns (exact count)
VERBS: dict[str, tuple[re.Pattern[str], ...]] = {
    "status": (),
    "health": (),
    "tls": (),
    "approvals": (),
    "history": (COUNT,),
    "submit-approval": (),          # signed approval envelope on stdin
    "upload": (RELEASE,),           # release archive on stdin
    "deploy": (APPROVAL_ID,),
    "rollback": (APPROVAL_ID,),
    "cancel": (APPROVAL_ID,),
}


class Refused(Exception):
    pass


def parse(command: str | None) -> list[str]:
    if command is None or not command.strip():
        raise Refused("no command given; this account has no shell (try: status)")
    if len(command) > 200:
        raise Refused("command too long")
    parts = command.split()
    # whitespace splitting only; every part must be a plain token, so quotes, $, ;, |, &,
    # backticks, redirections and globbing characters can never reach the broker
    for part in parts:
        if not TOKEN_RE.match(part):
            raise Refused(f"invalid characters in {part[:40]!r}")
    verb, args = parts[0], parts[1:]
    if verb not in VERBS:
        raise Refused(f"unknown command {verb!r}; allowed: {', '.join(sorted(VERBS))}")
    patterns = VERBS[verb]
    if verb == "history" and not args:
        args = ["20"]
    if len(args) != len(patterns):
        raise Refused(f"{verb} takes {len(patterns)} argument(s)")
    for value, pattern in zip(args, patterns):
        if not pattern.match(value):
            raise Refused(f"invalid argument for {verb}: {value[:40]!r}")
    if verb == "history" and not 1 <= int(args[0]) <= 200:
        raise Refused("history count must be 1-200")
    return [verb, *args]


def origin() -> str:
    client = os.environ.get("SSH_CLIENT", "").split()
    return client[0] if client and ORIGIN.match(client[0]) else "unknown"


def main() -> int:
    try:
        argv = parse(os.environ.get("SSH_ORIGINAL_COMMAND"))
    except Refused as exc:
        print(f"REFUSED: {exc}", file=sys.stderr)
        return 2
    # sudo -n: never prompt; the sudoers rule names exactly this broker path.
    os.execv(SUDO, [SUDO, "-n", "--", BROKER, *argv, "--origin", origin()])
    return 127  # not reached


if __name__ == "__main__":
    sys.exit(main())
