"""Operator CLI for approval-based Mushukistan web releases (runs on the operator machine).

    release-web prepare  --sha SHA --label LABEL [--client-id-from-live] [--skip-build --worktree DIR] [--nginx-gate]
    release-web approve  RELEASE [--ttl-minutes 120] [--no-auto-rollback] [--stage-only]   (OWNER)
    release-web approve-rollback RELEASE [--ttl-minutes 30]                                (OWNER)
    release-web revoke   APPROVAL_ID                                                       (OWNER)
    release-web deploy   RELEASE
    release-web rollback RELEASE
    release-web status | health | tls | approvals | history [N] | cancel APPROVAL_ID

PowerShell entry point: scripts/deploy/release-web.ps1. Settings come from the gitignored
scripts/deploy/local.env (see local.env.example). Design: docs/DEPLOYMENT_AUTOMATION.md.

`approve*` and `revoke` sign with the OWNER's key. They must be run by the owner in a real
terminal; the key must be a FIDO2 security key or passphrase-protected and must not be
loaded in ssh-agent, otherwise any local process (including an AI agent) could sign.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import re
import secrets
import subprocess
import sys
import threading
import time
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
sys.path.insert(0, str(HERE / "automation"))
import approval_schema as schema  # noqa: E402

DEFAULT_REQUIRED_CHECKS = ("Backend lint and format", "Backend tests (PostGIS)", "Flutter analyze and tests")
DEFAULT_OPERATIONS = ["stage", "backup", "activate", "auto-rollback"]
MIN_FREE_MB_FOR_BUILD = 2500
# Upload bounds (the server enforces its own: upload_idle_timeout / upload_max_seconds in broker.conf).
UPLOAD_STALL_SECONDS = 120     # no bytes accepted by ssh for this long: stop
UPLOAD_MAX_SECONDS = 1800      # whole transfer, including the server's hash check
UPLOAD_CHUNK = 256 * 1024
PROGRESS_SECONDS = 10
# sshd prints this for the deploy account, which has no home directory by design (harmless).
SSHD_NOISE = "Could not chdir to home directory /nonexistent: No such file or directory"


class CliError(Exception):
    pass


# --------------------------------------------------------------------------- settings
def load_settings(path: Path = HERE / "local.env") -> dict:
    settings = {}
    if path.is_file():
        for raw in path.read_text(encoding="utf-8").splitlines():
            line = raw.strip()
            if line and not line.startswith("#") and "=" in line:
                key, value = line.split("=", 1)
                settings[key.strip()] = value.strip().strip('"')
    for key in ("MUSHUKISTAN_DEPLOY_TARGET", "MUSHUKISTAN_DEPLOY_KEY", "MUSHUKISTAN_APPROVAL_KEY",
                "MUSHUKISTAN_ENVIRONMENT", "MUSHUKISTAN_BASH", "MUSHUKISTAN_REQUIRED_CHECKS"):
        if os.environ.get(key):
            settings[key] = os.environ[key]
    return settings


def setting(settings: dict, key: str) -> str:
    value = settings.get(key, "")
    if not value:
        raise CliError(f"{key} is not set (scripts/deploy/local.env; see local.env.example)")
    return value


def release_dir() -> Path:
    d = REPO / "release" / "automation"
    d.mkdir(parents=True, exist_ok=True)
    return d


def git(*args: str, cwd: Path = REPO) -> str:
    return subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True, text=True).stdout.strip()


def find_bash(settings: dict) -> str:
    if settings.get("MUSHUKISTAN_BASH"):
        return settings["MUSHUKISTAN_BASH"]
    for candidate in (r"C:\Program Files\Git\bin\bash.exe", "/usr/bin/bash", "/bin/bash"):
        if Path(candidate).is_file():
            return candidate
    raise CliError("Git Bash not found; set MUSHUKISTAN_BASH")


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


# --------------------------------------------------------------------------- CI gate
def evaluate_check_runs(payload: dict, required: tuple[str, ...]) -> list[str]:
    """Return problems; empty means every required check completed successfully."""
    runs = payload.get("check_runs", [])
    problems = []
    by_name: dict[str, list[dict]] = {}
    for run in runs:
        by_name.setdefault(run.get("name", ""), []).append(run)
    for name in required:
        if name not in by_name:
            problems.append(f"required check {name!r} has not run")
            continue
        latest = max(by_name[name], key=lambda r: r.get("started_at") or "")
        if latest.get("status") != "completed":
            problems.append(f"{name!r} is {latest.get('status')} (pending is not success)")
        elif latest.get("conclusion") != "success":
            problems.append(f"{name!r} concluded {latest.get('conclusion')}")
    for name, items in by_name.items():
        latest = max(items, key=lambda r: r.get("started_at") or "")
        if latest.get("status") == "completed" and latest.get("conclusion") not in ("success", "skipped", "neutral"):
            problems.append(f"check {name!r} concluded {latest.get('conclusion')}")
    return problems


def github_slug() -> str:
    url = git("remote", "get-url", "origin")
    m = re.search(r"github\.com[:/]+(?:[^/]+@)?([^/]+/[^/]+?)(?:\.git)?$", url) or \
        re.search(r"([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+?)(?:\.git)?$", url)
    if not m:
        raise CliError(f"cannot derive the GitHub repository from {url}")
    return m.group(1)


def check_ci(sha: str, required: tuple[str, ...]) -> list[str]:
    url = f"https://api.github.com/repos/{github_slug()}/commits/{sha}/check-runs?per_page=100"
    req = urllib.request.Request(url, headers={"Accept": "application/vnd.github+json", "User-Agent": "release-web"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        payload = json.load(resp)
    problems = evaluate_check_runs(payload, required)
    if problems:
        raise CliError("CI gate failed: " + "; ".join(problems))
    return [f"{r['name']}: {r['conclusion']} ({r.get('html_url', '')})" for r in payload["check_runs"]]


# --------------------------------------------------------------------------- prepare
def free_memory_mb() -> int:
    if os.name == "nt":
        out = subprocess.run(["powershell", "-NoProfile", "-Command",
                              "(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory"],
                             capture_output=True, text=True).stdout.strip()
        return int(out) // 1024 if out.isdigit() else 0
    with open("/proc/meminfo") as fh:
        info = dict(line.split(":", 1) for line in fh)
    return int(info["MemAvailable"].split()[0]) // 1024


def live_client_id() -> str:
    """The Google web client id is public: every visitor downloads it in main.dart.js."""
    with urllib.request.urlopen("https://mushukistan.uz/main.dart.js", timeout=240) as resp:
        body = resp.read().decode("utf-8", "replace")
    ids = sorted(set(re.findall(r"[0-9]{6,}-[a-z0-9]{20,}\.apps\.googleusercontent\.com", body)))
    if len(ids) != 1:
        raise CliError(f"expected exactly one client id in the live bundle, found {len(ids)}")
    return ids[0]


def cmd_prepare(args, settings) -> int:
    sha = args.sha
    if not re.fullmatch(r"[0-9a-f]{7,40}", sha):
        raise CliError("--sha must be a commit SHA")
    if not re.fullmatch(r"[A-Za-z0-9._-]{1,40}", args.label):
        raise CliError("--label: letters, digits, . _ - only")
    git("fetch", "--quiet", "origin", "main")
    sha = git("rev-parse", "--verify", f"{sha}^{{commit}}")
    remote_main = git("ls-remote", "origin", "refs/heads/main").split()[0]
    if subprocess.run(["git", "merge-base", "--is-ancestor", sha, remote_main], cwd=REPO).returncode != 0:
        raise CliError(f"{sha} is not on origin/main ({remote_main[:7]})")
    print(f"commit {sha} is on origin/main ({remote_main[:7]})")
    required = tuple(s.strip() for s in settings.get("MUSHUKISTAN_REQUIRED_CHECKS", "").split(",") if s.strip()) \
        or DEFAULT_REQUIRED_CHECKS
    checks = check_ci(sha, required)
    print("CI gate passed:\n  " + "\n  ".join(checks))

    wt = Path(args.worktree).resolve() if args.worktree else REPO.parent / f"{REPO.name}-release-{sha[:7]}"
    if not wt.exists():
        if args.worktree:
            raise CliError(f"--worktree {wt} does not exist")
        git("worktree", "add", "--detach", str(wt), sha)
    if git("rev-parse", "HEAD", cwd=wt) != sha or git("status", "--porcelain", "--untracked-files=no", cwd=wt):
        raise CliError(f"{wt} is not a clean checkout of {sha[:7]}")
    print(f"clean release worktree: {wt}")
    bash = find_bash(settings)

    if not args.skip_build:
        free = free_memory_mb()
        if free < MIN_FREE_MB_FOR_BUILD:
            raise CliError(f"only {free} MB RAM free; close emulators/heavy apps (need {MIN_FREE_MB_FOR_BUILD} MB)")
        env = dict(os.environ)
        if args.client_id_from_live:
            env["MUSHUKISTAN_GOOGLE_WEB_CLIENT_ID"] = live_client_id()
        if not env.get("MUSHUKISTAN_GOOGLE_WEB_CLIENT_ID"):
            raise CliError("set MUSHUKISTAN_GOOGLE_WEB_CLIENT_ID or pass --client-id-from-live")
        # one heavy step at a time (the laptop has run out of memory before)
        subprocess.run(["flutter", "clean"], cwd=wt / "frontend", check=True, shell=os.name == "nt",
                       stdout=subprocess.DEVNULL)
        subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
                        str(wt / "frontend/tool/build_production.ps1"), "-Target", "Web"], cwd=wt, env=env, check=True)
        py = sys.executable
        for step in ([py, "website/build.py"], [py, "-m", "unittest", "discover", "-s", "website", "-p", "test_*.py"],
                     ["node", "website/test_interactions.js"],
                     [py, "website/tool/check_flutter_bundle.py", "frontend/build/web"]):
            subprocess.run(step, cwd=wt, check=True)
        if args.nginx_gate:
            subprocess.run([py, "website/tool/check_nginx_http.py", "--flutter", "frontend/build/web",
                            "--website", "website/dist", "--report", ".data/nginx-http.json"], cwd=wt, check=True)
    for p in ("frontend/build/web/main.dart.js", "website/dist/index.html"):
        if not (wt / p).is_file():
            raise CliError(f"missing build output {p}; run without --skip-build")

    name_prefix = f"-{sha[:7]}-{args.label}"
    existing = sorted((wt / "release").glob(f"*{name_prefix}.tar.gz")) if (wt / "release").is_dir() else []
    if not existing:
        subprocess.run([bash, "scripts/deploy/package-release.sh", "--label", args.label], cwd=wt, check=True)
        existing = sorted((wt / "release").glob(f"*{name_prefix}.tar.gz"))
    tarball = existing[-1]
    name = tarball.name[: -len(".tar.gz")]
    schema.validate_release_name(name)
    plan = {"release": name, "commit": sha, "artifact": str(tarball), "artifact_sha256": sha256_file(tarball),
            "artifact_bytes": tarball.stat().st_size,
            "main_dart_js_sha256": sha256_file(wt / "frontend/build/web/main.dart.js"),
            "ci": checks, "worktree": str(wt), "scope": "web only: replaces only the Nginx container",
            "default_operations": DEFAULT_OPERATIONS, "prepared_at": schema.format_time(schema.utc_now())}
    plan_path = release_dir() / f"{name}.plan.json"
    plan_path.write_text(json.dumps(plan, indent=2))
    print_plan(plan)
    print(f"\nplan saved: {plan_path}\nNEXT (owner, in a real terminal): release-web approve {name}")
    return 0


def print_plan(plan: dict) -> None:
    print("\n=== RELEASE PLAN")
    for key in ("release", "commit", "artifact_sha256", "artifact_bytes", "main_dart_js_sha256", "scope"):
        print(f"  {key:<20}: {plan[key]}")
    print("  steps               : upload -> verify SHA-256 -> safe stage -> preflight (Compose, nginx -t, TLS)")
    print("                        -> fresh DB backup -> activate Nginx only -> public verification")
    print("                        -> automatic Nginx rollback on failed verification (if approved)")


def load_plan(name: str) -> dict:
    schema.validate_release_name(name)
    path = release_dir() / f"{name}.plan.json"
    if not path.is_file():
        raise CliError(f"no plan for {name}; run prepare first")
    plan = json.loads(path.read_text())
    if sha256_file(Path(plan["artifact"])) != plan["artifact_sha256"]:
        raise CliError("the artifact changed after prepare; run prepare again")
    return plan


# --------------------------------------------------------------------------- owner signing
def key_is_safe(key: Path, ssh_keygen: str = "ssh-keygen") -> tuple[bool, str]:
    pub = Path(str(key) + ".pub")
    kind = pub.read_text().split()[0] if pub.is_file() else ""
    if kind.startswith("sk-"):
        return True, "FIDO2 security key (touch required)"
    probe = subprocess.run([ssh_keygen, "-y", "-P", "", "-f", str(key)], capture_output=True, text=True)
    if probe.returncode == 0:
        return False, "the approval key has no passphrase"
    return True, "passphrase-protected key"


def require_owner_terminal() -> None:
    if not (sys.stdin.isatty() and sys.stdout.isatty()):
        raise CliError("owner commands need an interactive terminal (run them yourself, not through an agent)")


def sign(doc: dict, settings: dict, label: str) -> Path:
    key = Path(setting(settings, "MUSHUKISTAN_APPROVAL_KEY")).expanduser().resolve()
    if REPO in key.parents:
        raise CliError("the approval key must live outside the repository/workspace")
    safe, why = key_is_safe(key)
    if not safe:
        raise CliError(f"refusing to sign: {why}. Use a FIDO2 key or a passphrase (and keep it out of ssh-agent).")
    out_dir = release_dir() / "approvals"
    out_dir.mkdir(exist_ok=True)
    doc_path = out_dir / f"{label}.{doc['approval_id']}.json"
    doc_path.write_bytes(schema.canonical_bytes(doc))
    print(f"signing with {key.name} ({why}); you may be asked for the passphrase or a touch")
    subprocess.run(["ssh-keygen", "-Y", "sign", "-f", str(key), "-n", schema.NAMESPACE, str(doc_path)], check=True)
    sig = Path(str(doc_path) + ".sig")
    if not sig.is_file():
        raise CliError("ssh-keygen did not produce a signature")
    print(f"approval {doc['approval_id']} written: {doc_path.name} (+ .sig)")
    return doc_path


def confirm(phrase: str) -> None:
    answer = input(f'Type "{phrase}" to sign this approval: ')
    if answer.strip() != phrase:
        raise CliError("confirmation did not match; nothing signed")


def cmd_approve(args, settings) -> int:
    require_owner_terminal()
    plan = load_plan(args.release)
    ops = ["stage"] if args.stage_only else list(DEFAULT_OPERATIONS)
    if args.no_auto_rollback and "auto-rollback" in ops:
        ops.remove("auto-rollback")
    print_plan(plan)
    print(f"  operations          : {', '.join(ops)}")
    print(f"  valid for           : {args.ttl_minutes} minutes, environment {settings.get('MUSHUKISTAN_ENVIRONMENT', 'production')}")
    confirm(f"APPROVE {plan['release']}")
    doc = schema.new_release_document(
        approval_id=secrets.token_hex(16), environment=settings.get("MUSHUKISTAN_ENVIRONMENT", "production"),
        release=plan["release"], commit=plan["commit"], artifact_sha256=plan["artifact_sha256"], operations=ops,
        issued_at=schema.utc_now(), ttl_minutes=args.ttl_minutes)
    sign(doc, settings, plan["release"])
    print(f"NEXT: release-web deploy {plan['release']}")
    return 0


def cmd_approve_rollback(args, settings) -> int:
    require_owner_terminal()
    schema.validate_release_name(args.release)
    print(f"Rollback approval: Nginx will be switched back FROM {args.release} to the release recorded in its "
          f"PREVIOUS_STATE.txt (only if {args.release} is what Nginx currently runs).")
    confirm(f"ROLLBACK {args.release}")
    doc = schema.new_rollback_document(approval_id=secrets.token_hex(16),
                                       environment=settings.get("MUSHUKISTAN_ENVIRONMENT", "production"),
                                       release=args.release, issued_at=schema.utc_now(), ttl_minutes=args.ttl_minutes)
    sign(doc, settings, f"rollback-{args.release}")
    print(f"NEXT: release-web rollback {args.release}")
    return 0


def cmd_revoke(args, settings) -> int:
    require_owner_terminal()
    schema.validate_approval_id(args.approval_id)
    confirm(f"REVOKE {args.approval_id[:12]}")
    doc = schema.new_revocation_document(approval_id=secrets.token_hex(16),
                                         environment=settings.get("MUSHUKISTAN_ENVIRONMENT", "production"),
                                         revokes=args.approval_id, issued_at=schema.utc_now(), ttl_minutes=60)
    path = sign(doc, settings, f"revoke-{args.approval_id[:12]}")
    return submit(path, settings)


# --------------------------------------------------------------------------- server calls
def ssh_argv(settings: dict, *remote: str) -> list[str]:
    key = setting(settings, "MUSHUKISTAN_DEPLOY_KEY")
    target = setting(settings, "MUSHUKISTAN_DEPLOY_TARGET")
    return ["ssh", "-i", key, "-o", "BatchMode=yes", "-o", "IdentitiesOnly=yes", "-o", "StrictHostKeyChecking=yes",
            "-o", "ConnectTimeout=20", "-o", "ServerAliveInterval=30", "-o", "ServerAliveCountMax=4", target, *remote]


class _Feeder(threading.Thread):
    """Copies a file into ssh's stdin pipe in binary chunks and records progress. Writing
    through an explicit pipe (instead of handing ssh the file as stdin) keeps the bytes
    untouched on every platform and lets the caller see when ssh stops accepting data."""

    def __init__(self, pipe, path: Path):
        super().__init__(daemon=True)
        self.pipe, self.path = pipe, path
        self.total = path.stat().st_size
        self.sent = 0
        self.last_progress = time.monotonic()
        self.done = False
        self.error = ""

    def run(self) -> None:
        try:
            with open(self.path, "rb") as fh:
                while chunk := fh.read(UPLOAD_CHUNK):
                    self.pipe.write(chunk)
                    self.pipe.flush()
                    self.sent += len(chunk)
                    self.last_progress = time.monotonic()
            self.done = True
        except OSError as exc:   # ssh exited (connection lost) or was stopped
            self.error = f"{type(exc).__name__}: {exc}"
        finally:
            try:
                self.pipe.close()
            except OSError:
                pass


def remote(settings: dict, *verb: str, stdin_path: Path | None = None, stdin_bytes: bytes | None = None,
           log: list[str] | None = None) -> int:
    def emit(line: str) -> None:
        print(line, flush=True)
        if log is not None:
            log.append(line)

    stdin = subprocess.PIPE if stdin_path is not None or stdin_bytes is not None else subprocess.DEVNULL
    proc = subprocess.Popen(ssh_argv(settings, *verb), stdin=stdin, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT)

    def read_output() -> None:
        assert proc.stdout is not None
        for raw in proc.stdout:
            line = raw.decode("utf-8", "replace").rstrip()
            if line != SSHD_NOISE:
                emit(line)

    reader = threading.Thread(target=read_output, daemon=True)
    reader.start()
    feeder = None
    if stdin_bytes is not None:
        proc.stdin.write(stdin_bytes)
        proc.stdin.close()
    elif stdin_path is not None:
        feeder = _Feeder(proc.stdin, Path(stdin_path))
        feeder.start()
    start = last_report = time.monotonic()
    stopped = ""
    try:
        while proc.poll() is None:
            time.sleep(0.2)
            if feeder is None:
                continue
            now = time.monotonic()
            if not feeder.done and now - feeder.last_progress > UPLOAD_STALL_SECONDS:
                stopped = f"upload stalled: ssh accepted no data for {UPLOAD_STALL_SECONDS} s"
            elif now - start > UPLOAD_MAX_SECONDS:
                stopped = f"upload exceeded {UPLOAD_MAX_SECONDS} s"
            if stopped:
                proc.kill()
                break
            if now - last_report >= PROGRESS_SECONDS:
                last_report = now
                rate = feeder.sent / max(now - start, 0.001) / 1024
                emit(f"  upload progress: {feeder.sent / 1048576:.1f} of {feeder.total / 1048576:.1f} MB "
                     f"({100 * feeder.sent // max(feeder.total, 1)}%), {rate:.0f} KB/s")
    except KeyboardInterrupt:
        proc.kill()
        raise
    finally:
        rc = proc.wait()
        reader.join(10)
        if feeder is not None:
            feeder.join(10)
        if proc.stdout is not None:
            proc.stdout.close()
    if feeder is not None:
        elapsed = time.monotonic() - start
        emit(f"  upload sent {feeder.sent} of {feeder.total} bytes in {elapsed:.0f} s")
        if feeder.error and not stopped:
            emit(f"  upload interrupted: ssh stopped reading ({feeder.error})")
    if stopped:
        emit(f"STOPPED: {stopped}; the server deletes the partial upload (nothing is staged)")
        return 124
    return rc


def envelope(doc_path: Path) -> bytes:
    document = doc_path.read_bytes()
    schema.parse_document(document)
    sig = Path(str(doc_path) + ".sig").read_text()
    return json.dumps({"document": base64.b64encode(document).decode(), "signature": sig}).encode()


def submit(doc_path: Path, settings: dict, log: list[str] | None = None) -> int:
    return remote(settings, "submit-approval", stdin_bytes=envelope(doc_path), log=log)


def latest_approval(label: str) -> Path:
    files = sorted((release_dir() / "approvals").glob(f"{label}.*.json"), key=lambda p: p.stat().st_mtime)
    if not files:
        raise CliError(f"no signed approval for {label}; the owner must run approve first")
    return files[-1]


def cmd_deploy(args, settings) -> int:
    plan = load_plan(args.release)
    doc_path = latest_approval(plan["release"])
    doc = schema.parse_document(doc_path.read_bytes())
    if doc["artifact_sha256"] != plan["artifact_sha256"] or doc["commit"] != plan["commit"]:
        raise CliError("the signed approval does not match the prepared artifact")
    log: list[str] = []
    report = [f"# Deployment report: {plan['release']}", "", f"- commit `{plan['commit']}`",
              f"- artifact SHA-256 `{plan['artifact_sha256']}`", f"- approval `{doc['approval_id']}` "
              f"({', '.join(doc['operations'])}; expires {doc['expires_at']})", ""]
    steps = [("submit approval", lambda: submit(doc_path, settings, log)),
             ("upload artifact", lambda: remote(settings, "upload", plan["release"],
                                                stdin_path=Path(plan["artifact"]), log=log)),
             ("deploy", lambda: remote(settings, "deploy", doc["approval_id"], log=log))]
    rc = 0
    for title, action in steps:
        print(f"\n### {title}")
        log.append(f"### {title}")
        rc = action()
        if rc != 0:
            print(f"STOPPED: {title} failed (exit {rc})")
            break
    result = next((l.split("RESULT:", 1)[1].strip() for l in reversed(log) if "RESULT:" in l), "NOT COMPLETED")
    succeeded = deploy_succeeded(rc, result, doc["operations"])
    if succeeded and "DEPLOYED" in result and not args.skip_local_verify:
        bash = find_bash(settings)
        print("\n### local public verification")
        env = {k: v for k, v in os.environ.items() if k != "MSYS_NO_PATHCONV"}   # breaks verify-public on Windows
        v = subprocess.run([bash, "scripts/deploy/verify-public.sh", "--flutter-dir", "frontend/build/web"],
                           cwd=plan["worktree"], env=env, capture_output=True, text=True)
        print(v.stdout[-3000:])
        log.append("### local public verification")
        log.extend(v.stdout.splitlines())
        if v.returncode != 0:
            result += " (local verification FAILED - check from the server: release-web health)"
            succeeded = False
    report += [f"**Result: {result}**", "", "```", *log, "```"]
    path = release_dir() / f"{plan['release']}.report.md"
    path.write_text("\n".join(report), encoding="utf-8")
    print(f"\nRESULT: {result}\nreport: {path}")
    return 0 if succeeded else 1


def deploy_succeeded(rc: int, result: str, operations: list[str]) -> bool:
    """Success means the server did everything the approval asked for: a full release ends
    DEPLOYED; an approval without `activate` (stage-only, or stage + backup) ends STAGED."""
    if rc != 0:
        return False
    if "activate" in operations:
        return result.startswith("DEPLOYED")
    return result.startswith("STAGED")


def cmd_rollback(args, settings) -> int:
    doc_path = latest_approval(f"rollback-{args.release}")
    doc = schema.parse_document(doc_path.read_bytes())
    if submit(doc_path, settings) != 0:
        return 1
    return remote(settings, "rollback", doc["approval_id"])


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="release-web", description=__doc__.split("\n\n")[0])
    sub = parser.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("prepare")
    p.add_argument("--sha", required=True)
    p.add_argument("--label", required=True)
    p.add_argument("--client-id-from-live", action="store_true")
    p.add_argument("--skip-build", action="store_true")
    p.add_argument("--nginx-gate", action="store_true")
    p.add_argument("--worktree", help="reuse an existing clean, already built checkout of the commit")
    p = sub.add_parser("approve")
    p.add_argument("release")
    p.add_argument("--ttl-minutes", type=int, default=120)
    p.add_argument("--no-auto-rollback", action="store_true")
    p.add_argument("--stage-only", action="store_true")
    p = sub.add_parser("approve-rollback")
    p.add_argument("release")
    p.add_argument("--ttl-minutes", type=int, default=30)
    p = sub.add_parser("revoke")
    p.add_argument("approval_id")
    p = sub.add_parser("deploy")
    p.add_argument("release")
    p.add_argument("--skip-local-verify", action="store_true", help="disposable test targets only")
    sub.add_parser("rollback").add_argument("release")
    for name in ("status", "health", "tls", "approvals"):
        sub.add_parser(name)
    sub.add_parser("history").add_argument("count", nargs="?", default="20")
    sub.add_parser("cancel").add_argument("approval_id")
    args = parser.parse_args(argv)
    settings = load_settings()
    handlers = {"prepare": cmd_prepare, "approve": cmd_approve, "approve-rollback": cmd_approve_rollback,
                "revoke": cmd_revoke, "deploy": cmd_deploy, "rollback": cmd_rollback}
    try:
        if args.cmd in handlers:
            return handlers[args.cmd](args, settings)
        if args.cmd == "history":
            if not args.count.isdigit():
                raise CliError("history count must be a number")
            return remote(settings, "history", args.count)
        if args.cmd == "cancel":
            schema.validate_approval_id(args.approval_id)
            return remote(settings, "cancel", args.approval_id)
        return remote(settings, args.cmd)
    except (CliError, schema.ApprovalError, subprocess.CalledProcessError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
