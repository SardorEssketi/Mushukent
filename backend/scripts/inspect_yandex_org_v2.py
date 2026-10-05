"""Extract public organization identity and pin for manual V2 review.

Accepts explicit organization URLs. Makes no entity match or import decision.
"""

import json
import sys
import time
import urllib.request
from datetime import UTC, datetime

from backend.scripts.probe_places_v2_yandex import DATA, extract


def main() -> None:
    if len(sys.argv) < 2:
        raise SystemExit("Usage: python -m backend.scripts.inspect_yandex_org_v2 URL ...")
    out = DATA / "yandex_org_checks.jsonl"
    with out.open("a", encoding="utf-8") as handle:
        for url in sys.argv[1:]:
            if not url.startswith(("https://yandex.com/maps/org/", "https://yandex.uz/maps/org/")):
                raise ValueError(f"Not a public Yandex organization URL: {url}")
            with urllib.request.urlopen(
                urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"}), timeout=25
            ) as response:
                page = response.read().decode("utf-8", errors="replace")
            row = {
                "requested_url": url,
                **extract(page),
                "possibly_closed_text": any(
                    phrase in page
                    for phrase in ("Shut down", "Endi ishlamaydi", "This business moved")
                ),
                "checked_at": datetime.now(UTC).isoformat(),
            }
            handle.write(json.dumps(row, ensure_ascii=False) + "\n")
            print(json.dumps(row, ensure_ascii=True), flush=True)
            time.sleep(1.5)


if __name__ == "__main__":
    main()
