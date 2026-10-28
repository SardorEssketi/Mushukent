"""Stub docker + trusted scripts for broker unit tests. Writes executables into a temp dir.

The stub docker keeps a tiny JSON "production" state: which release directory Nginx runs from,
its Compose files and bind mounts, and the other container ids. `compose ... up ... nginx` run in
a release directory switches Nginx to that directory (like the real Compose project would).
"""
from __future__ import annotations

import json
import os
import stat
import textwrap
from pathlib import Path

DOCKER = r'''#!/usr/bin/env python3
import json, os, sys
state_path = os.environ["STUB_STATE"]
s = json.load(open(state_path))
a = sys.argv[1:]
log = open(state_path + ".log", "a"); log.write(" ".join(a) + "\n"); log.close()
def save(): json.dump(s, open(state_path, "w"))
if a[0] == "inspect":
    fmt = a[a.index("-f") + 1] if "-f" in a else ""
    name = a[-1]
    if name == "mushukistan-nginx" and os.environ.get("STUB_NO_NGINX"):
        print("Error: No such object: mushukistan-nginx", file=sys.stderr); sys.exit(1)
    if name != "mushukistan-nginx":
        if "State.Status" in fmt:
            print("running healthy restarts=0"); sys.exit(0)
        if "State.Running" in fmt: print("true"); sys.exit(0)
        sys.exit(0)
    if "working_dir" in fmt: print(s["working_dir"])
    elif "config_files" in fmt: print(",".join(s["files"]))
    elif "Mounts" in fmt:
        print(f"/usr/share/nginx/html={s['web']}"); print(f"/var/www/landing={s['landing']}")
        print(f"/var/www/certbot=/var/www/certbot")
    elif "State.Running" in fmt: print("true" if s.get("running", True) else "false")
    sys.exit(0)
if a[0] == "ps":
    if "-q" in a: print("w0rker"); sys.exit(0)
    print(f"mushukistan-nginx {s['nginx_id']} nginx:1.27-alpine Up")
    for n, i in s["others"].items(): print(f"{n} {i} img Up")
    sys.exit(0)
if a[0] == "compose":
    if os.environ.get("STUB_COMPOSE_FAIL"): sys.exit(1)
    cwd = os.getcwd()
    files = [a[i + 1] for i, x in enumerate(a) if x == "-f"]
    s["working_dir"] = cwd; s["files"] = files
    s["web"] = os.path.realpath(os.path.join(cwd, "frontend/build/web"))
    s["landing"] = os.path.realpath(os.path.join(cwd, "website/dist"))
    s["nginx_id"] = format(int(s["nginx_id"], 16) + 1, "012x")
    save(); sys.exit(0)
sys.exit(0)
'''

# Stands in for activate-web-release.sh: dry run / --execute with token check and a real switch
# through the stub docker; behaviour is steered by flag files in $STUB_FLAGS.
ACTIVATE = r'''#!/usr/bin/env bash
set -uo pipefail
. "$APPROVAL_TOKEN_LIB"
rel="$1"; shift; execute=0; token=""; backup=""
while [ $# -gt 0 ]; do case "$1" in --execute) execute=1; shift;; --approval-token) token="$2"; shift 2;; --backup-file) backup="$2"; shift 2;; *) shift;; esac; done
R="$REL_ROOT/$rel"
[ -f "$STUB_FLAGS/preflight-fail" ] && { echo "ERROR: nginx -t failed"; exit 1; }
[ -f "$STUB_FLAGS/preflight-warn" ] && echo "WARN  renewal webroot is 'x' but this release mounts 'y'"
if [ "$execute" -eq 0 ]; then echo "DRY RUN complete: all checks passed, nothing was changed."; exit 0; fi
[ -s "$backup" ] || { echo "ERROR: backup missing"; exit 1; }
id="$(check_approval_token "$token")" || exit 1
[ -f "$STUB_FLAGS/fail-before-switch" ] && { echo "ERROR: compose config failed"; exit 1; }
wd="$("$DOCKER_BIN" inspect -f '{{index .Config.Labels "com.docker.compose.project.working_dir"}}' mushukistan-nginx)"
files="$("$DOCKER_BIN" inspect -f '{{index .Config.Labels "com.docker.compose.project.config_files"}}' mushukistan-nginx)"
web="$("$DOCKER_BIN" inspect -f '{{range .Mounts}}{{.Destination}}={{.Source}}{{println}}{{end}}' mushukistan-nginx | sed -n 's#^/usr/share/nginx/html=##p')"
land="$("$DOCKER_BIN" inspect -f '{{range .Mounts}}{{.Destination}}={{.Source}}{{println}}{{end}}' mushukistan-nginx | sed -n 's#^/var/www/landing=##p')"
printf 'recorded_utc=x\napproval_id=%s\nprevious_working_dir=%s\nprevious_config_files=%s\nprevious_web=%s\nprevious_landing=%s\nrollback=cd x\ncontainer_ids_before:\n' \
  "$id" "$wd" "$files" "$web" "$land" > "$R/PREVIOUS_STATE.txt"
fl=""; for f in docker-compose.yml docker-compose.prod.yml; do fl="$fl -f $R/$f"; done
(cd "$R" && "$DOCKER_BIN" compose $fl up -d --no-deps --no-build --force-recreate nginx) || exit 1
bash "$VERIFY_SCRIPT" --flutter-dir "$R/frontend/build/web" || { echo "FAILED public verification."; exit 1; }
echo "Done."
'''

BACKUP = r'''#!/usr/bin/env bash
set -uo pipefail
. "$APPROVAL_TOKEN_LIB"
label=""; token=""
while [ $# -gt 0 ]; do case "$1" in --label) label="$2"; shift 2;; --approval-token) token="$2"; shift 2;; *) shift;; esac; done
out="$BACKUP_DIR/mushukistan-test-$label.dump"
echo "target file   : $out"
id="$(check_approval_token "$token")" || exit 1
[ -f "$STUB_FLAGS/backup-fail" ] && { echo "ERROR: pg_dump failed"; exit 1; }
echo dump > "$out"
echo "pg_restore --list entries: 240"
'''

VERIFY = r'''#!/usr/bin/env bash
dir="$2"
[ -f "$STUB_FLAGS/verify-fail" ] && [[ "$dir" == *"$(cat "$STUB_FLAGS/verify-fail")"* ]] && { echo "FAIL  main.dart.js"; exit 1; }
echo "ALL CHECKS PASSED"
'''

TLS = "#!/usr/bin/env bash\necho 'ALL TLS CHECKS PASSED'\n"


def write_exec(path: Path, body: str) -> str:
    path.write_text(textwrap.dedent(body) if body.startswith("\n") else body)
    path.chmod(path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    return str(path)


def make_release_dir(root: Path, name: str, label: str, commit: str = "") -> Path:
    d = root / name
    (d / "frontend/build/web").mkdir(parents=True, exist_ok=True)
    (d / "website/dist").mkdir(parents=True, exist_ok=True)
    (d / "frontend/build/web/index.html").write_text(f"<html>{label}</html>")
    (d / "frontend/build/web/main.dart.js").write_text(f"// {label}")
    (d / "website/dist/index.html").write_text(f"landing {label}")
    for f in ("docker-compose.yml", "docker-compose.prod.yml"):
        (d / f).write_text("services: {}\n")
    if commit:
        (d / "RELEASE_COMMIT.txt").write_text(commit + "\n")
    return d


def install(tmp: Path, repo_deploy_dir: Path) -> dict:
    bin_dir = tmp / "bin"
    bin_dir.mkdir()
    flags = tmp / "flags"
    flags.mkdir()
    rel_root = tmp / "releases"
    rel_root.mkdir()
    backups = tmp / "backups"
    backups.mkdir()
    active = make_release_dir(rel_root, "20260101-aaaaaaa-old", "OLD")
    (active / ".env").write_text("POSTGRES_PASSWORD=supersecretvalue\nKEY=1\n")
    os.chmod(active / ".env", 0o600)
    (active / "docker-compose.notification-release.yml").write_text("services: {}\n")
    state = tmp / "docker.json"
    state.write_text(json.dumps({
        "working_dir": str(active), "files": [str(active / "docker-compose.yml"), str(active / "docker-compose.prod.yml")],
        "web": str(active / "frontend/build/web"), "landing": str(active / "website/dist"),
        "nginx_id": "00000000000a", "others": {"mushukistan-backend": "bbbbbbbbbbbb", "mushukistan-db": "dddddddddddd"}}))
    env = {"STUB_STATE": str(state), "STUB_FLAGS": str(flags),
           "APPROVAL_TOKEN_LIB": str(repo_deploy_dir / "approval-token.sh")}
    return {
        "docker": write_exec(bin_dir / "docker", DOCKER),
        "activate": write_exec(bin_dir / "activate.sh", ACTIVATE),
        "backup": write_exec(bin_dir / "backup.sh", BACKUP),
        "verify": write_exec(bin_dir / "verify.sh", VERIFY),
        "tls": write_exec(bin_dir / "tls.sh", TLS),
        "rel_root": rel_root, "backups": backups, "flags": flags, "state": state, "active": active, "env": env,
    }
