"""Break a py-spy raw (collapsed) profile of the backend into cost categories.

    python tools/pyspy_breakdown.py results/pyspy/stacks_threads.txt

"self" = the library the CPU was executing in (deepest frame that matches a category);
"inclusive" = share of samples with that component anywhere on the stack.
"""

from __future__ import annotations

import re
import sys
from collections import Counter

SELF_RULES = [  # (category, regex on "function (file:line)"), first match from the leaf wins
    ("psycopg (driver, incl. waiting on the DB socket)", r"psycopg/"),
    ("SQLAlchemy ORM/Core", r"sqlalchemy/"),
    ("GeoAlchemy/Shapely", r"geoalchemy2/|shapely/"),
    ("Pydantic validation/serialisation", r"pydantic|pydantic_core"),
    ("python-jose / JWT decode", r"jose/|ecdsa/|cryptography/"),
    ("PostHog capture + OTLP log export", r"posthog/|opentelemetry/|google/protobuf|urllib3/|requests/|http/client"),
    ("structlog / logging", r"structlog/|logging/"),
    ("JSON encode/decode", r"json/|orjson"),
    ("FastAPI routing/dependencies", r"fastapi/"),
    ("Starlette middleware/request", r"starlette/"),
    ("anyio/asyncio/threading (thread hand-off, event loop)", r"anyio/|asyncio/|threading\.py|concurrent/"),
    ("uvicorn/httptools (HTTP parsing)", r"uvicorn/|httptools"),
    ("app code", r"/app/app/|\(app/"),
    ("load-test shim (not in production)", r"sitecustomize"),
]
INCLUSIVE = {
    "rate-limit middleware (incl. its JWT decode)": r"rate_limit\.py",
    "JWT decode anywhere": r"decode_access_token|jose/jwt",
    "PostHog context middleware (main.py)": r"__call__ \(app/main\.py",
    "PostHog/OTLP threads + capture": r"posthog/|opentelemetry/",
    "structlog/logging": r"structlog/|logging/",
    "Pydantic": r"pydantic",
    "SQLAlchemy": r"sqlalchemy/",
    "psycopg": r"psycopg/",
    "feed endpoints": r"read_feed|list_feed|list_mixed_feed",
    "cats/map endpoints": r"list_cats|cats\.py",
    "views endpoints": r"record_seen|record_post_view|views\.py",
    "auth user lookup (get_current_user)": r"get_current_user|get_optional_current_user",
}


def main() -> None:
    selfc: Counter[str] = Counter()
    incl: Counter[str] = Counter()
    threads: Counter[str] = Counter()
    leaves: Counter[str] = Counter()
    total = 0
    for line in open(sys.argv[1], encoding="utf-8", errors="replace"):
        stack, _, count = line.rstrip("\n").rpartition(" ")
        if not count.isdigit():
            continue
        n = int(count)
        total += n
        frames = stack.split(";")
        threads[frames[0].split(" (")[0]] += n
        leaves[frames[-1][:110]] += n
        for frame in reversed(frames):
            category = next((c for c, rx in SELF_RULES if re.search(rx, frame)), None)
            if category:
                selfc[category] += n
                break
        else:
            selfc["other / interpreter"] += n
        for name, rx in INCLUSIVE.items():
            if any(re.search(rx, frame) for frame in frames):
                incl[name] += n
    pct = lambda n: f"{100 * n / total:5.1f}%"  # noqa: E731
    print(f"samples {total}\n\n== self time by library")
    for name, n in selfc.most_common():
        print(f"{pct(n)}  {name}")
    print("\n== inclusive (component on the stack)")
    for name, n in incl.most_common():
        print(f"{pct(n)}  {name}")
    print("\n== by thread")
    for name, n in threads.most_common(8):
        print(f"{pct(n)}  {name}")
    print("\n== top leaf frames")
    for name, n in leaves.most_common(15):
        print(f"{pct(n)}  {name}")


if __name__ == "__main__":
    main()
