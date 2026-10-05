"""Read-only production place export over the established SSH path.

The SQL file opens a read-only transaction and rolls it back. SSH stdout is
written as raw UTF-8 bytes so Cyrillic names are not changed by PowerShell.
No database credentials or production settings are copied to the workstation.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SQL = ROOT / "backend" / "scripts" / "sql" / "places_v2_production_inventory.sql"
OUTPUT = ROOT / "data" / "places_v2" / "output" / "production_places_readonly_export.jsonl"
SSH_OPTIONS = [
    "ssh",
    "-o",
    "BatchMode=yes",
    "-o",
    "StrictHostKeyChecking=yes",
    "-o",
    "ConnectTimeout=10",
]
REMOTE_QUERY = (
    "docker exec -i mushukistan-db psql -X -qAt -v ON_ERROR_STOP=1 " "-U mushukistan -d mushukistan"
)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--ssh-target", required=True, help="Explicit SSH host or user@host")
    args = parser.parse_args()
    if not re.fullmatch(r"(?:[A-Za-z0-9_]+@)?[A-Za-z0-9][A-Za-z0-9.-]*", args.ssh_target):
        parser.error("--ssh-target must be a host or user@host")
    if OUTPUT.exists():
        raise FileExistsError(f"Refusing to overwrite production export: {OUTPUT}")
    sql = SQL.read_bytes()
    if b"BEGIN TRANSACTION READ ONLY;" not in sql or b"ROLLBACK;" not in sql:
        raise RuntimeError("Export SQL must use a read-only transaction and rollback")
    result = subprocess.run(
        [*SSH_OPTIONS, args.ssh_target, REMOTE_QUERY],
        input=sql,
        capture_output=True,
        timeout=90,
        check=False,
    )
    if result.returncode:
        raise RuntimeError(f"Read-only SSH export failed (exit {result.returncode})")
    lines = [line for line in result.stdout.splitlines() if line.strip()]
    rows = [json.loads(line.decode("utf-8")) for line in lines]
    ids = [row["id"] for row in rows]
    if len(ids) != len(set(ids)):
        raise RuntimeError("Production export has duplicate UUIDs")
    OUTPUT.write_bytes(b"\n".join(lines) + (b"\n" if lines else b""))
    print(json.dumps({"production_places_exported": len(rows), "output": str(OUTPUT)}))


if __name__ == "__main__":
    main()
