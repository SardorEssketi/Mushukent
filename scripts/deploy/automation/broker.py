#!/usr/bin/python3 -I
"""Mushukistan approval broker (runs as root, ON the production server).

Installed root-owned as /usr/local/lib/mushukistan-deploy/broker. The restricted
`mushukistan-deploy` account reaches it only through deploy-gate and one sudo rule. It:

  * verifies owner-signed approvals (ssh-keygen -Y verify against a root-owned
    allowed_signers file) and stores them in a root-only state directory;
  * accepts an uploaded release archive only if its SHA-256 equals the approved one;
  * stages it with a safe extractor (no links, no absolute paths, no "..");
  * runs the TRUSTED, root-owned copies of activate-web-release.sh / backup-db.sh /
    verify-public.sh (never scripts from the uploaded archive);
  * replaces only the Nginx container, and rolls it back automatically only when the
    approval includes auto-rollback;
  * logs every security-relevant action (no secrets) to an append-only audit log.

Design and threat model: docs/DEPLOYMENT_AUTOMATION.md. Standard library only.
"""
from __future__ import annotations

import base64
import fcntl
import hashlib
import json
import os
import re
import secrets
import shutil
import signal
import stat
import subprocess
import sys
import tarfile
import tempfile
import time
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path, PurePosixPath

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
import approval_schema as schema  # noqa: E402  (root-owned file next to the broker)

CONFIG_PATH = "/etc/mushukistan-deploy/broker.conf"
SAFE_PATH = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
PRIVATE_FILES = (".env", "docker-compose.notification-release.yml")
STAGE_MARKER = ".deploy-approval"
SECRET_LINE = re.compile(
    r"(?i)\b([A-Z0-9_]*(PASSWORD|SECRET|TOKEN|API_KEY|PRIVATE_KEY|DATABASE_URL|DSN)[A-Z0-9_]*)\s*[=:]\s*\S+")


class Refused(Exception):
    """A request that must not proceed. Nothing was changed unless the message says so."""


# --------------------------------------------------------------------------- config
@dataclass
class Config:
    environment: str = "production"
    rel_root: str = "/opt/mushukistan-releases"
    state_dir: str = "/var/lib/mushukistan-deploy"
    token_dir: str = "/run/mushukistan-deploy"
    allowed_signers: str = "/etc/mushukistan-deploy/allowed_signers"
    signer_identity: str = "mushukistan-owner"
    max_ttl_minutes: int = 120
    max_artifact_mb: int = 200
    max_unpacked_mb: int = 1024
    max_members: int = 20000
    activate_script: str = "/usr/local/lib/mushukistan-deploy/activate-web-release.sh"
    backup_script: str = "/usr/local/lib/mushukistan-deploy/backup-db.sh"
    verify_script: str = "/usr/local/lib/mushukistan-deploy/verify-public.sh"
    tls_check_script: str = "/usr/local/lib/mushukistan-tls/check-tls.sh"
    backup_dir: str = "/root/mushukistan-backups"
    docker: str = "/usr/bin/docker"
    ssh_keygen: str = "/usr/bin/ssh-keygen"
    bash: str = "/bin/bash"
    curl: str = "/usr/bin/curl"
    nginx_container: str = "mushukistan-nginx"
    db_container: str = "mushukistan-db"
    backend_container: str = "mushukistan-backend"
    project: str = "mushukistan"
    health_url: str = "https://api.mushukistan.uz/api/v1/health"
    nginx_wait_tries: int = 30
    extra_env: dict = field(default_factory=dict)  # tests only; never read from the config file

    INT_KEYS = ("max_ttl_minutes", "max_artifact_mb", "max_unpacked_mb", "max_members", "nginx_wait_tries")

    @classmethod
    def load(cls, path: str) -> "Config":
        cfg = cls()
        known = {f for f in cls.__dataclass_fields__ if f != "extra_env"}
        with open(path, encoding="utf-8") as fh:
            for number, raw in enumerate(fh, 1):
                line = raw.strip()
                if not line or line.startswith("#"):
                    continue
                key, sep, value = line.partition("=")
                key = key.strip().lower()
                if not sep or key not in known:
                    raise Refused(f"{path}:{number}: unknown or malformed setting")
                value = value.strip()
                setattr(cfg, key, int(value) if key in cls.INT_KEYS else value)
        if not 5 <= cfg.max_ttl_minutes <= 24 * 60:
            raise Refused("max_ttl_minutes must be 5..1440")
        if not schema.ENVIRONMENT_RE.match(cfg.environment):
            raise Refused("environment setting is invalid")
        return cfg


def assert_trusted(path: str) -> None:
    """Root-owned and not writable by group/other, for the file and every parent."""
    p = Path(path)
    if not p.exists():
        raise Refused(f"trusted path missing: {path}")
    for item in [p, *p.parents]:
        st = item.lstat()
        if stat.S_ISLNK(st.st_mode):
            st = item.stat()
        if st.st_uid != 0 or st.st_mode & (stat.S_IWGRP | stat.S_IWOTH):
            raise Refused(f"{item} must be owned by root and not group/world-writable")


# --------------------------------------------------------------------------- output
class Out:
    """Writes progress to the SSH client; keeps going if the client disconnects."""

    def __init__(self, stream=None):
        self.stream = stream if stream is not None else sys.stdout
        self.lines: list[str] = []
        self.client_gone = False

    def __call__(self, text: str = "") -> None:
        for line in str(text).splitlines() or [""]:
            line = SECRET_LINE.sub(lambda m: f"{m.group(1)}=***", line)
            self.lines.append(line)
            if self.client_gone:
                continue
            try:
                self.stream.write(line + "\n")
                self.stream.flush()
            except (BrokenPipeError, OSError):
                self.client_gone = True


# --------------------------------------------------------------------------- broker
class Broker:
    def __init__(self, cfg: Config, *, stdin=None, out: Out | None = None, now=None, origin="unknown"):
        self.cfg = cfg
        self.stdin = stdin if stdin is not None else sys.stdin.buffer
        self.out = out or Out()
        self._now = now
        self.origin = origin
        self.state = Path(cfg.state_dir)
        self.approvals_dir = self.state / "approvals"
        self.artifacts_dir = self.state / "artifacts"
        self.tmp_dir = self.state / "tmp"
        self.audit_path = self.state / "audit.log"
        for d in (self.state, self.approvals_dir, self.artifacts_dir, self.tmp_dir):
            d.mkdir(mode=0o700, parents=True, exist_ok=True)
            os.chmod(d, 0o700)
        token_dir = Path(cfg.token_dir)
        token_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
        os.chmod(token_dir, 0o700)
        self._lock_fh = None

    # ---- helpers -----------------------------------------------------------------
    def now(self) -> datetime:
        return self._now() if callable(self._now) else (self._now or schema.utc_now())

    def audit(self, verb: str, result: str, *, approval_id: str = "", release: str = "", detail: str = "") -> None:
        entry = {"ts": schema.format_time(schema.utc_now()), "verb": verb, "origin": self.origin,
                 "approval_id": approval_id, "release": release, "result": result,
                 "detail": SECRET_LINE.sub(lambda m: f"{m.group(1)}=***", detail)[:300]}
        fd = os.open(self.audit_path, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o600)
        try:
            os.write(fd, (json.dumps(entry, sort_keys=True) + "\n").encode())
            os.fsync(fd)
        finally:
            os.close(fd)

    def lock(self) -> None:
        self._lock_fh = open(self.state / "lock", "a+")
        try:
            fcntl.flock(self._lock_fh, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            self._lock_fh.close()
            self._lock_fh = None
            raise Refused("another deployment operation is running; try again later") from None
        self._cleanup_stale()

    def unlock(self) -> None:
        if self._lock_fh:
            fcntl.flock(self._lock_fh, fcntl.LOCK_UN)
            self._lock_fh.close()
            self._lock_fh = None

    def _cleanup_stale(self) -> None:
        """Holding the lock means no other broker runs: leftovers are from an interruption."""
        for p in self.artifacts_dir.glob("*.partial"):
            p.unlink(missing_ok=True)
        for p in self.tmp_dir.iterdir():
            shutil.rmtree(p) if p.is_dir() else p.unlink(missing_ok=True)
        for p in Path(self.cfg.token_dir).glob("*.token"):
            p.unlink(missing_ok=True)
        rel_root = Path(self.cfg.rel_root)
        if rel_root.is_dir():
            for p in rel_root.glob(".staging-*"):
                shutil.rmtree(p, ignore_errors=True)
        for rec_path in self.approvals_dir.glob("*.json"):
            rec = json.loads(rec_path.read_text())
            if rec.get("status") in ("activating", "rolling-back"):
                rec["status"] = "interrupted"
                rec.setdefault("events", []).append(
                    {"at": schema.format_time(self.now()), "event": "interrupted while " + rec.get("step", "?")})
                self._write_record(rec)
                self.audit("recover", "interrupted", approval_id=rec["approval_id"], release=rec.get("release", ""),
                           detail="previous run stopped during " + rec.get("step", "?") + "; production state must be inspected")

    def env(self) -> dict:
        env = {"PATH": SAFE_PATH, "LANG": "C.UTF-8", "HOME": "/root",
               "DOCKER_BIN": self.cfg.docker, "REL_ROOT": self.cfg.rel_root,
               "NGINX_CONTAINER": self.cfg.nginx_container, "DB_CONTAINER": self.cfg.db_container,
               "BACKUP_DIR": self.cfg.backup_dir, "VERIFY_SCRIPT": self.cfg.verify_script,
               "APPROVAL_TOKEN_DIR": self.cfg.token_dir}
        env.update(self.cfg.extra_env)
        return env

    def run(self, argv: list[str], *, cwd: str | None = None, timeout: int = 1800, quiet=False) -> tuple[int, list[str]]:
        lines: list[str] = []
        deadline = time.monotonic() + timeout
        with subprocess.Popen(argv, cwd=cwd, env=self.env(), stdin=subprocess.DEVNULL,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, errors="replace") as proc:
            assert proc.stdout is not None
            for line in proc.stdout:
                line = line.rstrip("\n")
                lines.append(line)
                if not quiet:
                    self.out("  | " + line)
                if time.monotonic() > deadline:
                    proc.kill()
                    lines.append("ERROR: timed out")
                    break
            rc = proc.wait()
        return rc, lines

    def docker_out(self, *args: str) -> str:
        rc, lines = self.run([self.cfg.docker, *args], quiet=True, timeout=120)
        if rc != 0:
            raise Refused(f"docker {args[0]} failed")
        return "\n".join(lines).strip()

    def write_token(self, approval_id: str) -> Path:
        path = Path(self.cfg.token_dir) / f"{secrets.token_hex(16)}.token"
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "w") as fh:
            fh.write(approval_id)
        os.chmod(path, 0o600)
        return path

    # ---- records -----------------------------------------------------------------
    def _record_path(self, approval_id: str) -> Path:
        return self.approvals_dir / f"{schema.validate_approval_id(approval_id)}.json"

    def _write_record(self, rec: dict) -> None:
        path = self._record_path(rec["approval_id"])
        tmp = path.with_suffix(".json.tmp")
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w") as fh:
            json.dump(rec, fh, sort_keys=True, indent=1)
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp, path)

    def _read_record(self, approval_id: str) -> dict:
        path = self._record_path(approval_id)
        if not path.exists():
            raise Refused("no such approval has been submitted")
        return json.loads(path.read_text())

    def verify_signature(self, document: bytes, signature: str) -> None:
        if not signature.startswith("-----BEGIN SSH SIGNATURE-----") or len(signature) > 8192:
            raise Refused("signature is not an SSH signature")
        work = Path(tempfile.mkdtemp(dir=self.tmp_dir))
        try:
            sig_path = work / "approval.sig"
            sig_path.write_text(signature)
            proc = subprocess.run(
                [self.cfg.ssh_keygen, "-Y", "verify", "-f", self.cfg.allowed_signers,
                 "-I", self.cfg.signer_identity, "-n", schema.NAMESPACE, "-s", str(sig_path)],
                input=document, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env={"PATH": SAFE_PATH},
                timeout=30)
        finally:
            shutil.rmtree(work, ignore_errors=True)
        if proc.returncode != 0 or b"Good" not in proc.stdout:
            raise Refused("approval signature is not valid for the owner identity")

    def valid_approval(self, approval_id: str, kind: str) -> tuple[dict, dict]:
        """Re-verify a stored approval before every use: status, signature, scope, time."""
        rec = self._read_record(approval_id)
        if rec["status"] != "active":
            raise Refused(f"approval is {rec['status']}; a new owner approval is required")
        document = base64.b64decode(rec["document_b64"])
        self.verify_signature(document, rec["signature"])
        doc = schema.parse_document(document)
        if doc["type"] != kind:
            raise Refused(f"approval type is {doc['type']}, this operation needs {kind}")
        if doc["environment"] != self.cfg.environment:
            raise Refused("approval is for a different environment")
        try:
            schema.check_time(doc, self.now(), self.cfg.max_ttl_minutes)
        except schema.ApprovalError as exc:
            if "expired" in str(exc):
                rec["status"] = "expired"
                self._write_record(rec)
            raise
        return rec, doc

    def step(self, rec: dict, name: str, result: str) -> None:
        rec.setdefault("steps", {})[name] = {"at": schema.format_time(self.now()), "result": result}
        self._write_record(rec)

    # ---- read-only ---------------------------------------------------------------
    def active_deployment(self) -> dict:
        label = lambda key: self.docker_out("inspect", "-f", "{{index .Config.Labels \"" + key + "\"}}",
                                            self.cfg.nginx_container)
        mounts = self.docker_out("inspect", "-f",
                                 "{{range .Mounts}}{{.Destination}}={{.Source}}{{println}}{{end}}",
                                 self.cfg.nginx_container)
        src = dict(line.split("=", 1) for line in mounts.splitlines() if "=" in line)
        web = os.path.realpath(src.get("/usr/share/nginx/html", ""))
        return {"working_dir": label("com.docker.compose.project.working_dir"),
                "config_files": label("com.docker.compose.project.config_files"),
                "web": web, "landing": os.path.realpath(src.get("/var/www/landing", "")),
                "acme": src.get("/var/www/certbot", "")}

    def sha256_file(self, path: str | Path) -> str:
        h = hashlib.sha256()
        with open(path, "rb") as fh:
            for chunk in iter(lambda: fh.read(1 << 20), b""):
                h.update(chunk)
        return h.hexdigest()

    def containers(self) -> list[str]:
        return self.docker_out("ps", "-a", "--filter", f"label=com.docker.compose.project={self.cfg.project}",
                               "--format", "{{.Names}} {{.ID}} {{.Image}} {{.Status}}").splitlines()

    def cmd_status(self) -> int:
        a = self.active_deployment()
        self.out(f"active Nginx release : {os.path.basename(a['working_dir'])}")
        self.out(f"web served from      : {a['web']}")
        self.out(f"landing served from  : {a['landing']}")
        main_js = Path(a["web"]) / "main.dart.js"
        if main_js.is_file():
            self.out(f"served main.dart.js  : {self.sha256_file(main_js)}")
        self.out("containers:")
        for line in sorted(self.containers()):
            self.out("  " + line)
        self.cmd_approvals(only_open=True)
        return 0

    def cmd_health(self) -> int:
        bad = 0
        for name in (self.cfg.db_container, self.cfg.backend_container):
            state = self.docker_out("inspect", "-f", "{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{end}} restarts={{.RestartCount}}", name)
            ok = state.startswith("running") and "unhealthy" not in state
            bad += not ok
            self.out(f"{'PASS' if ok else 'FAIL'}  {name}: {state}")
        workers = self.docker_out("ps", "-q", "--filter", f"label=com.docker.compose.project={self.cfg.project}",
                                  "--filter", "label=com.docker.compose.service=notification-worker")
        self.out(f"{'PASS' if workers else 'FAIL'}  notification worker running: {'yes' if workers else 'no'}")
        bad += not workers
        rc, _ = self.run([self.cfg.curl, "-sf", "--max-time", "20", "-o", "/dev/null", self.cfg.health_url], quiet=True)
        self.out(f"{'PASS' if rc == 0 else 'FAIL'}  API health {self.cfg.health_url}")
        bad += rc != 0
        return 1 if bad else 0

    def cmd_tls(self) -> int:
        rc, _ = self.run([self.cfg.bash, self.cfg.tls_check_script, "--all"])
        return rc

    def cmd_approvals(self, only_open: bool = False) -> int:
        self.out("approvals:" if not only_open else "open approvals:")
        shown = 0
        for path in sorted(self.approvals_dir.glob("*.json"), key=lambda p: p.stat().st_mtime):
            rec = json.loads(path.read_text())
            if only_open and rec["status"] not in ("active", "activating", "rolling-back", "interrupted"):
                continue
            steps = ",".join(f"{k}:{v['result']}" for k, v in rec.get("steps", {}).items())
            self.out(f"  {rec['approval_id']} {rec['type']:<12} {rec.get('release', rec.get('revokes', '')):<40} "
                     f"{rec['status']:<11} expires {rec['expires_at']} {steps}")
            shown += 1
        if not shown:
            self.out("  (none)")
        return 0

    def cmd_history(self, count: int) -> int:
        if not self.audit_path.exists():
            self.out("(no history)")
            return 0
        for line in self.audit_path.read_text().splitlines()[-count:]:
            e = json.loads(line)
            self.out(f"{e['ts']} {e['verb']:<15} {e['result']:<12} {e['approval_id'][:12]:<12} {e['release']:<40} {e['detail']}")
        return 0

    # ---- approvals -----------------------------------------------------------------
    def cmd_submit_approval(self) -> int:
        raw = self.stdin.read(32769)
        if len(raw) > 32768:
            raise Refused("approval envelope too large")
        try:
            env = json.loads(raw)
            if not isinstance(env, dict) or set(env) != {"document", "signature"}:
                raise ValueError("envelope must have exactly document and signature")
            document = base64.b64decode(env["document"], validate=True)
            signature = env["signature"]
            if not isinstance(signature, str):
                raise ValueError("signature must be text")
        except (ValueError, TypeError) as exc:
            raise Refused(f"malformed approval envelope: {exc}") from None
        doc = schema.parse_document(document)
        self.verify_signature(document, signature)
        if doc["environment"] != self.cfg.environment:
            raise Refused(f"approval is for environment {doc['environment']!r}, this server is {self.cfg.environment!r}")
        schema.check_time(doc, self.now(), self.cfg.max_ttl_minutes)
        path = self._record_path(doc["approval_id"])
        if path.exists():
            existing = json.loads(path.read_text())
            if existing["document_b64"] == base64.b64encode(document).decode() and existing["status"] == "active":
                self.out(f"approval {doc['approval_id']} was already submitted (still active)")
                return 0
            raise Refused(f"approval id {doc['approval_id']} was already used (status {existing['status']}); replay refused")
        rec = {"approval_id": doc["approval_id"], "type": doc["type"], "document_b64": base64.b64encode(document).decode(),
               "signature": signature, "received_at": schema.format_time(self.now()), "expires_at": doc["expires_at"],
               "status": "active", "steps": {}, "events": []}
        if doc["type"] == "revocation":
            rec["revokes"] = doc["revokes"]
            rec["status"] = "consumed"
            self._write_record(rec)
            target = self._record_path(doc["revokes"])
            if target.exists():
                t = json.loads(target.read_text())
                if t["status"] in ("activating", "rolling-back"):
                    self.out("WARN  the revoked approval is executing right now; the running step completes")
                t["status"] = "revoked" if t["status"] in ("active", "interrupted", "activating", "rolling-back") else t["status"]
                t.setdefault("events", []).append({"at": schema.format_time(self.now()), "event": f"revoked by {doc['approval_id']}"})
                self._write_record(t)
            else:
                # keep a placeholder so the revoked id can never be submitted later
                self._write_record({"approval_id": doc["revokes"], "type": "unknown", "document_b64": "", "signature": "",
                                    "received_at": schema.format_time(self.now()), "expires_at": doc["expires_at"],
                                    "status": "revoked", "steps": {}, "events": [{"event": f"pre-revoked by {doc['approval_id']}"}]})
            self.audit("revoke", "ok", approval_id=doc["revokes"], detail=f"revocation {doc['approval_id']}")
            self.out(f"approval {doc['revokes']} revoked")
            return 0
        rec["release"] = doc["release"]
        self._write_record(rec)
        scope = ",".join(doc["operations"])
        self.audit("submit-approval", "ok", approval_id=doc["approval_id"], release=doc["release"],
                   detail=f"{doc['type']} ops={scope} expires={doc['expires_at']}")
        self.out(f"approval {doc['approval_id']} accepted: {doc['type']} {doc['release']} [{scope}] until {doc['expires_at']}")
        return 0

    def cmd_cancel(self, approval_id: str) -> int:
        rec = self._read_record(approval_id)
        if rec["status"] != "active":
            raise Refused(f"approval is {rec['status']}; only an active approval can be cancelled")
        rec["status"] = "cancelled"
        self._write_record(rec)
        self.audit("cancel", "ok", approval_id=approval_id, release=rec.get("release", ""))
        self.out(f"approval {approval_id} cancelled")
        return 0

    # ---- upload ------------------------------------------------------------------
    def approval_for_release(self, release: str) -> tuple[dict, dict]:
        matches = []
        for path in self.approvals_dir.glob("*.json"):
            rec = json.loads(path.read_text())
            if rec.get("release") == release and rec["type"] == "web-release" and rec["status"] == "active":
                matches.append(rec["approval_id"])
        if not matches:
            raise Refused(f"no active owner approval for {release}; submit the signed approval first")
        if len(matches) > 1:
            raise Refused(f"{len(matches)} active approvals name {release}; cancel all but one")
        return self.valid_approval(matches[0], "web-release")

    def cmd_upload(self, release: str) -> int:
        schema.validate_release_name(release)
        rec, doc = self.approval_for_release(release)
        final = self.artifacts_dir / f"{release}.tar.gz"
        if final.exists() and self.sha256_file(final) == doc["artifact_sha256"]:
            self.out("artifact already uploaded and verified")
            while self.stdin.read(1 << 20):   # drain the client's copy without buffering it
                pass
            return 0
        limit = self.cfg.max_artifact_mb * 1024 * 1024
        partial = self.artifacts_dir / f"{release}.tar.gz.partial"
        h = hashlib.sha256()
        size = 0
        try:
            fd = os.open(partial, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
            with os.fdopen(fd, "wb") as fh:
                while chunk := self.stdin.read(1 << 20):
                    size += len(chunk)
                    if size > limit:
                        raise Refused(f"artifact exceeds {self.cfg.max_artifact_mb} MB")
                    h.update(chunk)
                    fh.write(chunk)
            if h.hexdigest() != doc["artifact_sha256"]:
                rec["upload_failures"] = rec.get("upload_failures", 0) + 1
                if rec["upload_failures"] >= 3:
                    rec["status"] = "failed"
                self.step(rec, "upload", "hash-mismatch")
                raise Refused(f"artifact SHA-256 {h.hexdigest()} does not match the approved {doc['artifact_sha256']}")
            os.replace(partial, final)
        finally:
            partial.unlink(missing_ok=True)
        self.step(rec, "upload", "ok")
        self.audit("upload", "ok", approval_id=rec["approval_id"], release=release, detail=f"{size} bytes, sha256 verified")
        self.out(f"uploaded {size} bytes; SHA-256 matches the approval")
        return 0

    # ---- staging -----------------------------------------------------------------
    def safe_extract(self, archive: Path, release: str) -> Path:
        rel_root = Path(self.cfg.rel_root)
        target = rel_root / release
        if target.exists() or target.is_symlink():
            raise Refused(f"{target} already exists and was not staged by this approval")
        limit = self.cfg.max_unpacked_mb * 1024 * 1024
        staging = Path(tempfile.mkdtemp(prefix=f".staging-{release}-", dir=rel_root))
        try:
            with tarfile.open(archive, "r:gz") as tf:
                members, total = [], 0
                for m in tf:
                    name = m.name
                    if name.startswith("/") or "\\" in name or "\x00" in name:
                        raise Refused(f"archive entry has an unsafe path: {name[:80]!r}")
                    parts = PurePosixPath(name).parts
                    if not parts or parts[0] != release or any(p in ("..", ".") for p in parts):
                        raise Refused(f"archive entry is outside {release}/: {name[:80]!r}")
                    if not (m.isreg() or m.isdir()):
                        raise Refused(f"archive entry is a link or special file: {name[:80]!r}")
                    if m.mode & (stat.S_ISUID | stat.S_ISGID):
                        raise Refused(f"archive entry has setuid/setgid bits: {name[:80]!r}")
                    total += m.size
                    if total > limit or len(members) >= self.cfg.max_members:
                        raise Refused("archive is too large when unpacked")
                    members.append(m)
                tf.extractall(staging, members=members, filter="data")
            for p in staging.rglob("*"):
                if p.is_symlink():
                    raise Refused("unexpected link after extraction")
                os.chmod(p, 0o755 if p.is_dir() or os.stat(p).st_mode & stat.S_IXUSR else 0o644)
            src = staging / release
            if not src.is_dir():
                raise Refused("archive does not contain the release directory")
            os.rename(src, target)
        finally:
            shutil.rmtree(staging, ignore_errors=True)
        return target

    def stage(self, rec: dict, doc: dict) -> Path:
        release = doc["release"]
        rel = Path(self.cfg.rel_root) / release
        marker = rel / STAGE_MARKER
        if rel.exists():
            if not (marker.is_file() and marker.read_text().strip() == doc["approval_id"]):
                raise Refused(f"{rel} exists but was not staged by approval {doc['approval_id']}; refusing to reuse it")
            self.out(f"release directory already staged by this approval: {rel}")
        else:
            archive = self.artifacts_dir / f"{release}.tar.gz"
            if not archive.is_file():
                raise Refused("artifact has not been uploaded")
            if self.sha256_file(archive) != doc["artifact_sha256"]:
                raise Refused("stored artifact no longer matches the approved SHA-256")
            self.safe_extract(archive, release)
            marker.write_text(doc["approval_id"] + "\n")
            self.out(f"extracted {release} safely into {rel}")
        commit_file = rel / "RELEASE_COMMIT.txt"
        if not commit_file.is_file() or commit_file.read_text().strip() != doc["commit"]:
            raise Refused("RELEASE_COMMIT.txt does not match the approved commit")
        active_dir = Path(self.active_deployment()["working_dir"])
        if not str(active_dir.resolve()).startswith(str(Path(self.cfg.rel_root).resolve()) + "/"):
            raise Refused("active Compose working directory is outside the release root")
        for name in PRIVATE_FILES:
            src, dst = active_dir / name, rel / name
            if not src.is_file():
                raise Refused(f"active release lacks {name}; cannot stage private files")
            if dst.exists():
                if dst.read_bytes() != src.read_bytes():
                    raise Refused(f"{name} in the staged release differs from the active one")
                continue
            shutil.copy2(src, dst)
            st = src.stat()
            os.chown(dst, st.st_uid, st.st_gid)
            os.chmod(dst, stat.S_IMODE(st.st_mode))
        self.out("private files copied from the active release (values never printed)")
        self.step(rec, "stage", "ok")
        self.audit("stage", "ok", approval_id=doc["approval_id"], release=release)
        return rel

    def preflight(self, rec: dict, doc: dict) -> None:
        self.out("== preflight: trusted activate-web-release.sh dry run")
        rc, lines = self.run([self.cfg.bash, self.cfg.activate_script, doc["release"]])
        text = "\n".join(lines)
        if rc != 0 or ("DRY RUN complete" not in text and "already what Nginx serves" not in text):
            self.step(rec, "preflight", "failed")
            raise Refused("preflight failed; nothing was changed")
        for warning in ("WARN  renewal webroot", "WARN  certificate renewal", "WARN  cannot read"):
            if warning in text:
                self.step(rec, "preflight", "failed")
                raise Refused(f"preflight warning is fatal in the automated path: {warning.strip()}")
        self.step(rec, "preflight", "ok")

    def backup(self, rec: dict, doc: dict) -> str:
        self.out("== backup: trusted backup-db.sh (authorized by the approval token)")
        token = self.write_token(doc["approval_id"])
        try:
            rc, lines = self.run([self.cfg.bash, self.cfg.backup_script, "--label", f"auto-{doc['commit'][:7]}",
                                  "--execute", "--approval-token", str(token)])
        finally:
            token.unlink(missing_ok=True)
        target = next((l.split(":", 1)[1].strip() for l in lines if l.startswith("target file")), "")
        entries = next((l.rsplit(":", 1)[1].strip() for l in lines if l.startswith("pg_restore --list entries")), "0")
        if rc != 0 or not target or not Path(target).is_file() or Path(target).stat().st_size == 0 \
                or not entries.isdigit() or int(entries) <= 10:
            self.step(rec, "backup", "failed")
            raise Refused("database backup failed or could not be verified; nothing was activated")
        if not str(Path(target).resolve()).startswith(str(Path(self.cfg.backup_dir).resolve()) + "/"):
            self.step(rec, "backup", "failed")
            raise Refused("backup was written outside the backup directory")
        rec["backup_file"] = target
        self.step(rec, "backup", "ok")
        self.audit("backup", "ok", approval_id=doc["approval_id"], release=doc["release"],
                   detail=f"{os.path.basename(target)} entries={entries}")
        return target

    def other_container_ids(self) -> list[str]:
        return sorted(l.split()[0] + " " + l.split()[1] for l in self.containers()
                      if not l.startswith(self.cfg.nginx_container + " "))

    # ---- rollback ----------------------------------------------------------------
    def read_previous_state(self, rel: Path) -> dict:
        path = rel / "PREVIOUS_STATE.txt"
        if not path.is_file():
            raise Refused(f"{path} is missing; cannot determine the rollback target")
        state = {}
        for line in path.read_text().splitlines():
            if line.startswith("container_ids_before"):
                break
            key, sep, value = line.partition("=")
            if sep and key in ("approval_id", "previous_working_dir", "previous_config_files",
                               "previous_web", "previous_landing"):
                state[key] = value.strip()
        root = str(Path(self.cfg.rel_root).resolve()) + "/"
        prev = Path(state.get("previous_working_dir", ""))
        if not prev.is_absolute() or not str(prev.resolve()).startswith(root) or not prev.is_dir():
            raise Refused("rollback target directory is missing or outside the release root")
        files = [f for f in state.get("previous_config_files", "").split(",") if f]
        if not files or any(Path(f).parent != prev or not Path(f).is_file() for f in files):
            raise Refused("rollback Compose files are missing or not in the rollback directory")
        for key in ("previous_web", "previous_landing"):
            d = Path(state.get(key, ""))
            if not d.is_absolute() or not (d / "index.html").is_file():
                raise Refused(f"rollback {key} is missing: {d}")
        state["files"] = files
        return state

    def nginx_rollback(self, rel: Path) -> bool:
        st = self.read_previous_state(rel)
        prev = st["previous_working_dir"]
        argv = [self.cfg.docker, "compose"]
        if self.docker_out("ps", "-q", "--filter", f"label=com.docker.compose.project={self.cfg.project}",
                           "--filter", "label=com.docker.compose.service=notification-worker"):
            argv += ["--profile", "notifications"]
        for f in st["files"]:
            argv += ["-f", f]
        argv += ["up", "-d", "--no-deps", "--no-build", "--force-recreate", "nginx"]
        self.out(f"== rollback: Nginx back to {os.path.basename(prev)}")
        rc, _ = self.run(argv, cwd=prev)
        if rc != 0:
            self.out("ERROR: compose up for the rollback failed")
            return False
        for _ in range(self.cfg.nginx_wait_tries):
            if self.docker_out("inspect", "-f", "{{.State.Running}}", self.cfg.nginx_container) == "true":
                break
            time.sleep(2)
        else:
            self.out("ERROR: Nginx is not running after the rollback")
            return False
        a = self.active_deployment()
        if a["web"] != os.path.realpath(st["previous_web"]) or a["landing"] != os.path.realpath(st["previous_landing"]):
            self.out("ERROR: Nginx mounts do not match the rollback target")
            return False
        rc, _ = self.run([self.cfg.bash, self.cfg.verify_script, "--flutter-dir", st["previous_web"]])
        self.out("rollback verification " + ("passed" if rc == 0 else "FAILED"))
        return rc == 0

    # ---- deploy ------------------------------------------------------------------
    def cmd_deploy(self, approval_id: str) -> int:
        rec, doc = self.valid_approval(approval_id, "web-release")
        ops = doc["operations"]
        release = doc["release"]
        self.out(f"== deploying {release} ({doc['commit'][:7]}) with approval {approval_id} [{','.join(ops)}]")
        rel = self.stage(rec, doc)
        self.preflight(rec, doc)
        if "backup" not in ops:
            rec["status"] = "consumed"
            self.step(rec, "deploy", "staged-only")
            self.audit("deploy", "staged-only", approval_id=approval_id, release=release)
            self.out("RESULT: STAGED (approval did not include backup/activate)")
            return 0
        dump = self.backup(rec, doc)
        if "activate" not in ops:
            rec["status"] = "consumed"
            self.step(rec, "deploy", "backed-up-only")
            self.audit("deploy", "backed-up-only", approval_id=approval_id, release=release)
            self.out("RESULT: STAGED AND BACKED UP (approval did not include activate)")
            return 0
        others_before = self.other_container_ids()
        rec["status"], rec["step"] = "activating", "activate"
        self._write_record(rec)
        self.audit("activate", "started", approval_id=approval_id, release=release)
        token = self.write_token(approval_id)
        try:
            rc, lines = self.run([self.cfg.bash, self.cfg.activate_script, release, "--execute",
                                  "--backup-file", dump, "--approval-token", str(token)])
        finally:
            token.unlink(missing_ok=True)
        prev_state = rel / "PREVIOUS_STATE.txt"
        switched = prev_state.is_file() and f"approval_id={approval_id}" in prev_state.read_text()
        others_after = self.other_container_ids()
        if others_after != others_before:
            self.out("WARN  backend/worker/database container ids changed during activation")
        if rc == 0:
            rc_tls, _ = self.run([self.cfg.bash, self.cfg.tls_check_script, "--server"])
            rec["status"] = "consumed"
            self.step(rec, "activate", "ok" if rc_tls == 0 else "ok-tls-warning")
            self.audit("activate", "ok", approval_id=approval_id, release=release,
                       detail="verified; tls " + ("ok" if rc_tls == 0 else "WARN"))
            self.out("RESULT: DEPLOYED AND VERIFIED" + ("" if rc_tls == 0 else " (TLS consistency warning)"))
            return 0
        if not switched:
            rec["status"] = "failed"
            self.step(rec, "activate", "failed-before-switch")
            self.audit("activate", "failed", approval_id=approval_id, release=release, detail="nothing switched")
            self.out("RESULT: FAILED BEFORE ACTIVATION (Nginx was not replaced)")
            return 1
        if "auto-rollback" not in ops:
            rec["status"] = "failed"
            self.step(rec, "activate", "failed-after-switch")
            self.audit("activate", "failed", approval_id=approval_id, release=release,
                       detail="switched; approval has no auto-rollback")
            self.out("RESULT: ACTIVATION FAILED AFTER THE SWITCH. The approval does not include auto-rollback:")
            self.out(f"        request an owner-signed web-rollback approval for {release} and run rollback.")
            return 1
        rec["status"], rec["step"] = "rolling-back", "auto-rollback"
        self._write_record(rec)
        ok = self.nginx_rollback(rel)
        rec["status"] = "failed"
        self.step(rec, "auto-rollback", "ok" if ok else "failed")
        self.audit("auto-rollback", "ok" if ok else "failed", approval_id=approval_id, release=release)
        self.out("RESULT: ROLLED BACK" if ok else "RESULT: ROLLBACK FAILED - inspect production immediately")
        return 1

    def cmd_rollback(self, approval_id: str) -> int:
        rec, doc = self.valid_approval(approval_id, "web-rollback")
        release = doc["release"]
        active = os.path.basename(self.active_deployment()["working_dir"])
        if active != release:
            raise Refused(f"the approval rolls back {release}, but Nginx currently runs {active}")
        rel = Path(self.cfg.rel_root) / release
        self.read_previous_state(rel)  # validates the target before anything changes
        others_before = self.other_container_ids()
        rec["status"], rec["step"] = "rolling-back", "rollback"
        self._write_record(rec)
        self.audit("rollback", "started", approval_id=approval_id, release=release)
        ok = self.nginx_rollback(rel)
        if self.other_container_ids() != others_before:
            self.out("WARN  backend/worker/database container ids changed during rollback")
        rec["status"] = "consumed"
        self.step(rec, "rollback", "ok" if ok else "failed")
        self.audit("rollback", "ok" if ok else "failed", approval_id=approval_id, release=release)
        self.out("RESULT: ROLLED BACK" if ok else "RESULT: ROLLBACK FAILED - inspect production immediately")
        return 0 if ok else 1

    # ---- dispatch ----------------------------------------------------------------
    def dispatch(self, verb: str, args: list[str]) -> int:
        read_only = {"status": self.cmd_status, "health": self.cmd_health, "tls": self.cmd_tls,
                     "approvals": self.cmd_approvals}
        if verb in read_only and not args:
            return read_only[verb]()
        if verb == "history" and len(args) == 1 and args[0].isdigit():
            return self.cmd_history(min(int(args[0]), 200))
        changing = {"submit-approval": (0, self.cmd_submit_approval), "upload": (1, self.cmd_upload),
                    "deploy": (1, self.cmd_deploy), "rollback": (1, self.cmd_rollback),
                    "cancel": (1, self.cmd_cancel)}
        if verb not in changing or len(args) != changing[verb][0]:
            raise Refused("unknown command or wrong arguments")
        self.lock()
        try:
            return changing[verb][1](*args)
        finally:
            self.unlock()


def main(argv: list[str]) -> int:
    signal.signal(signal.SIGHUP, signal.SIG_IGN)   # a dropped SSH session must not abort a switch
    signal.signal(signal.SIGPIPE, signal.SIG_IGN)
    out = Out()
    origin = "unknown"
    if len(argv) >= 2 and argv[-2] == "--origin":
        origin = argv[-1] if re.match(r"^[0-9A-Fa-f:.]{2,45}$", argv[-1]) else "invalid"
        argv = argv[:-2]
    if not argv:
        print("usage: broker <verb> [args]", file=sys.stderr)
        return 2
    verb, args = argv[0], argv[1:]
    try:
        if os.geteuid() != 0:
            raise Refused("the broker must run as root (through sudo from deploy-gate)")
        if sys.version_info < (3, 12):
            raise Refused("Python 3.12+ is required (safe tar extraction filters)")
        assert_trusted(os.path.realpath(__file__))
        assert_trusted(os.path.join(os.path.dirname(os.path.realpath(__file__)), "approval_schema.py"))
        assert_trusted(CONFIG_PATH)
        cfg = Config.load(CONFIG_PATH)
        for path in (cfg.allowed_signers, cfg.activate_script, cfg.backup_script, cfg.verify_script,
                     cfg.tls_check_script, os.path.join(os.path.dirname(cfg.activate_script), "approval-token.sh")):
            assert_trusted(path)
        broker = Broker(cfg, out=out, origin=origin)
    except (Refused, OSError) as exc:
        print(f"REFUSED: {exc}", file=sys.stderr)
        return 2
    try:
        return broker.dispatch(verb, args)
    except (Refused, schema.ApprovalError) as exc:
        aid = args[0] if args and schema.APPROVAL_ID_RE.match(args[0]) else ""
        broker.audit(verb, "refused", approval_id=aid, detail=str(exc))
        out(f"REFUSED: {exc}")
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
