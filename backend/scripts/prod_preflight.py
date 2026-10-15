"""Read-only production configuration preflight.

Usage (on the operator's machine or the server, never in CI):

    python scripts/prod_preflight.py --env-file /path/to/production.env

It loads the settings exactly as the API would, runs the application's own production validation,
and adds checks the validator does not cover. It prints only check names and PASS/FAIL/WARN;
it never prints a value, opens a network connection or writes anything.
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

from pydantic import ValidationError

# Allow `python scripts/prod_preflight.py` from the backend directory.
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.core.config import Settings  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[2]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--env-file", required=True, type=Path)
    args = parser.parse_args()
    if not args.env_file.is_file():
        print("FAIL env file not found")
        return 2

    results: list[tuple[str, str, str]] = []

    def check(status: str, name: str, hint: str = "") -> None:
        results.append((status, name, hint))

    try:
        settings = Settings(_env_file=args.env_file)  # type: ignore[call-arg]
    except ValidationError as exc:
        # include_input=False keeps submitted values (possibly secrets) out of the output.
        for error in exc.errors(include_input=False, include_url=False):
            location = ".".join(str(part) for part in error["loc"]) or "settings"
            check("FAIL", f"application validation: {location}", error["msg"])
        _print(results)
        return 1

    check("PASS", "application production validation (APP_ENV, secrets, R2, Firebase, CORS, mail)")
    check(
        "PASS" if settings.app_env == "production" else "FAIL",
        "APP_ENV is exactly production",
        "staging is allowed by the app but this checklist is for production",
    )
    check("PASS" if not settings.app_debug else "FAIL", "APP_DEBUG is false")
    check("PASS" if settings.rate_limit_enabled else "FAIL", "RATE_LIMIT_ENABLED is true")
    check(
        "PASS" if len(settings.jwt_secret_key) >= 48 else "WARN",
        "JWT secret length is at least 48 characters (length only is checked)",
    )
    check(
        "PASS" if not settings.enable_api_docs else "WARN",
        "interactive API docs are disabled",
    )
    check(
        "PASS" if settings.posthog_project_token or not settings.posthog_required else "FAIL",
        "analytics: configured, or optional",
    )
    check(
        "PASS" if settings.r2_public_base_url.startswith("https://") else "FAIL",
        "R2_PUBLIC_BASE_URL uses https",
    )
    check(
        (
            "PASS"
            if all(origin.startswith("https://") for origin in settings.allowed_cors_origins)
            else "FAIL"
        ),
        "every CORS origin uses https",
    )
    check(
        "PASS" if settings.public_app_base_url.startswith("https://") else "FAIL",
        "PUBLIC_APP_BASE_URL uses https",
    )
    if settings.rate_limit_backend == "memory":
        dockerfile = (REPO_ROOT / "backend" / "Dockerfile").read_text(encoding="utf-8")
        single_worker = "--workers" not in dockerfile
        check(
            "PASS" if single_worker else "FAIL",
            "in-memory rate limiting with exactly one uvicorn worker (Dockerfile)",
            "" if single_worker else "use RATE_LIMIT_BACKEND=redis or a single worker",
        )
    broad = [net for net in settings.trusted_proxy_cidrs if net.prefixlen == 0]
    check("PASS" if not broad else "FAIL", "TRUSTED_PROXY_CIDRS does not trust every address")
    check(
        "PASS" if (REPO_ROOT / "infrastructure" / "nginx" / "default.conf").is_file() else "WARN",
        "nginx config present in the checkout",
    )
    check(
        "WARN",
        "manual: backup taken and restore rehearsed; rollback images retained",
        "see docs/audits/final-release-gate/PRODUCTION_PREFLIGHT.md",
    )
    _print(results)
    return 1 if any(status == "FAIL" for status, _, _ in results) else 0


def _print(results: list[tuple[str, str, str]]) -> None:
    for status, name, hint in results:
        suffix = f" ({hint})" if hint else ""
        print(f"{status:4} {name}{suffix}")
    failed = sum(1 for status, _, _ in results if status == "FAIL")
    print(f"\n{len(results)} checks, {failed} failed. No values were printed.")


if __name__ == "__main__":
    os.environ.setdefault("PYTHONDONTWRITEBYTECODE", "1")
    raise SystemExit(main())
