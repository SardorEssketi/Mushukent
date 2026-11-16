"""Refuse a run whose test access tokens expire before it ends (exit 5).

Expired tokens make every signed-in session start with 401 + refresh, which silently turns a normal
run into a refresh-storm run (found 2026-11-16). Reads the exp claim of results/tokens.json without
verifying the signature (the harness minted it).

    python tools/token_check.py [min_hours]     default 3
"""

from __future__ import annotations

import base64
import json
import sys
import time
from pathlib import Path

TOKENS = Path(__file__).resolve().parent.parent / "results" / "tokens.json"


def exp_of(token: str) -> int:
    payload = token.split(".")[1]
    payload += "=" * (-len(payload) % 4)
    return int(json.loads(base64.urlsafe_b64decode(payload))["exp"])


def main() -> int:
    min_hours = float(sys.argv[1]) if len(sys.argv) > 1 else 3.0
    users = json.loads(TOKENS.read_text(encoding="utf-8"))["users"]
    left_h = (min(exp_of(u["token"]) for u in users) - time.time()) / 3600
    if left_h < min_hours:
        print(f"token_check: test access tokens expire in {left_h:.1f} h (< {min_hours} h). "
              "Re-mint: docker compose ... --profile tools run --rm seed --tokens-only", file=sys.stderr)
        return 5
    print(f"token_check: test access tokens valid for {left_h:.1f} h")
    return 0


if __name__ == "__main__":
    sys.exit(main())
