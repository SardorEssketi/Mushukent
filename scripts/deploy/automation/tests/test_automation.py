"""Unit and negative tests for the approval broker, the SSH gate, the approval schema, the
approval-token check of the shell scripts, and the operator CLI helpers.

Linux only (fcntl, POSIX permissions). Needs ssh-keygen and bash. Runs as a normal user:
root-only checks are exercised by the disposable end-to-end test (e2e_automation.sh).
    python3 -m unittest discover -s scripts/deploy/automation/tests -v
"""
from __future__ import annotations

import base64
import io
import json
import os
import subprocess
import sys
import tarfile
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
AUTOMATION = HERE.parent
DEPLOY = AUTOMATION.parent
sys.path[:0] = [str(AUTOMATION), str(DEPLOY), str(HERE)]

import approval_schema as schema  # noqa: E402
import broker as broker_mod  # noqa: E402
import deploy_gate  # noqa: E402
import release_web  # noqa: E402
import stubs  # noqa: E402

NOW = datetime(2026, 10, 24, 10, 0, 0, tzinfo=timezone.utc)
COMMIT = "5b4bd33824fb1a3386a359314b665f0580d93740"
RELEASE = "20261024-5b4bd33-feed"


def keygen(path: Path) -> Path:
    subprocess.run(["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-C", "test", "-f", str(path)], check=True)
    return path


class Base(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.TemporaryDirectory()
        self.tmp = Path(self.tmpdir.name)
        self.owner = keygen(self.tmp / "owner")
        self.intruder = keygen(self.tmp / "intruder")
        signers = self.tmp / "allowed_signers"
        signers.write_text(f'mushukistan-owner namespaces="{schema.NAMESPACE}" '
                           + (self.tmp / "owner.pub").read_text())
        self.s = stubs.install(self.tmp, DEPLOY)
        self.cfg = broker_mod.Config(
            rel_root=str(self.s["rel_root"]), state_dir=str(self.tmp / "state"), token_dir=str(self.tmp / "tokens"),
            allowed_signers=str(signers), activate_script=self.s["activate"], backup_script=self.s["backup"],
            verify_script=self.s["verify"], tls_check_script=self.s["tls"], backup_dir=str(self.s["backups"]),
            docker=self.s["docker"], ssh_keygen="ssh-keygen", bash="bash", curl="true", nginx_wait_tries=2,
            max_ttl_minutes=120)
        self.cfg.extra_env = self.s["env"]
        self.now = NOW
        self.cfg.source_archive_url = f"file://{self.tmp}/src/{{commit}}.tar.gz"
        self.make_source(COMMIT)

    def make_source(self, commit: str, mutate=None) -> None:
        """Stand-in for codeload.github.com: the commit's tracked files (no build outputs)."""
        d = self.tmp / "srcwork" / f"Mushukent-{commit}"
        d.mkdir(parents=True, exist_ok=True)
        for f in ("docker-compose.yml", "docker-compose.prod.yml"):
            (d / f).write_text("services: {}\n")
        if mutate:
            mutate(d)
        (self.tmp / "src").mkdir(exist_ok=True)
        with tarfile.open(self.tmp / "src" / f"{commit}.tar.gz", "w:gz") as tf:
            tf.add(d, arcname=d.name)

    def tearDown(self):
        self.tmpdir.cleanup()

    # -- helpers --------------------------------------------------------------------
    def broker(self, stdin: bytes = b"") -> broker_mod.Broker:
        self.output = io.StringIO()
        return broker_mod.Broker(self.cfg, stdin=io.BytesIO(stdin), out=broker_mod.Out(self.output),
                                 now=lambda: self.now)

    def sign(self, doc: dict, key: Path | None = None, namespace: str = schema.NAMESPACE) -> bytes:
        raw = schema.canonical_bytes(doc)
        path = self.tmp / f"doc-{doc['approval_id']}.json"
        path.write_bytes(raw)
        sig = Path(str(path) + ".sig")
        sig.unlink(missing_ok=True)
        subprocess.run(["ssh-keygen", "-q", "-Y", "sign", "-f", str(key or self.owner), "-n", namespace, str(path)],
                       check=True, capture_output=True)
        return json.dumps({"document": base64.b64encode(raw).decode(), "signature": sig.read_text()}).encode()

    def release_doc(self, *, sha256="0" * 64, ops=None, release=RELEASE, commit=COMMIT, issued=None, ttl=60,
                    env="production", approval_id=None) -> dict:
        doc = {"version": 1, "type": "web-release", "approval_id": approval_id or os.urandom(16).hex(),
               "environment": env, "release": release, "commit": commit, "artifact_sha256": sha256,
               "operations": ops or ["stage", "backup", "activate", "auto-rollback"],
               "issued_at": schema.format_time(issued or NOW),
               "expires_at": schema.format_time((issued or NOW) + timedelta(minutes=ttl))}
        return doc

    def submit(self, doc: dict, **kw) -> int:
        return self.broker(self.sign(doc, **kw)).cmd_submit_approval()

    def record(self, approval_id: str) -> dict:
        return json.loads((Path(self.cfg.state_dir) / "approvals" / f"{approval_id}.json").read_text())

    def make_archive(self, release=RELEASE, commit=COMMIT, label="NEW", extra=None, mutate=None) -> bytes:
        src = self.tmp / "archive-src"
        d = stubs.make_release_dir(src, release, label, commit)
        if mutate:
            mutate(d)
        buf = io.BytesIO()
        with tarfile.open(fileobj=buf, mode="w:gz") as tf:
            tf.add(d, arcname=release)
            for member, data in (extra or []):
                tf.addfile(member, io.BytesIO(data) if data is not None else None)
        return buf.getvalue()

    def approved_upload(self, archive: bytes, ops=None) -> str:
        import hashlib
        doc = self.release_doc(sha256=hashlib.sha256(archive).hexdigest(), ops=ops)
        self.assertEqual(self.submit(doc), 0)
        self.assertEqual(self.broker(archive).cmd_upload(RELEASE), 0)
        return doc["approval_id"]

    def flag(self, name: str, content: str = "") -> None:
        (self.s["flags"] / name).write_text(content)

    def docker_state(self) -> dict:
        return json.loads(self.s["state"].read_text())


# =============================================================================== schema
class SchemaTests(Base):
    def test_valid_document_roundtrip(self):
        doc = self.release_doc()
        self.assertEqual(schema.parse_document(schema.canonical_bytes(doc))["release"], RELEASE)

    def test_non_canonical_rejected(self):
        raw = json.dumps(self.release_doc(), indent=1).encode()
        with self.assertRaisesRegex(schema.ApprovalError, "canonical"):
            schema.parse_document(raw)

    def test_extra_or_missing_fields_rejected(self):
        doc = self.release_doc()
        doc["extra"] = 1
        with self.assertRaisesRegex(schema.ApprovalError, "fields"):
            schema.parse_document(schema.canonical_bytes(doc))

    def test_release_must_match_commit(self):
        doc = self.release_doc(release="20261024-aaaaaaa-feed")
        with self.assertRaisesRegex(schema.ApprovalError, "match the commit"):
            schema.parse_document(schema.canonical_bytes(doc))

    def test_scope_rules(self):
        for ops, msg in ((["activate", "stage"], "requires backup"), (["stage", "auto-rollback"], "requires activate"),
                         (["backup"], "include stage"), (["stage", "stage"], "distinct"), (["stage", "rm"], "distinct")):
            with self.subTest(ops=ops), self.assertRaisesRegex(schema.ApprovalError, msg):
                schema.parse_document(schema.canonical_bytes(self.release_doc(ops=ops)))

    def test_time_rules(self):
        doc = self.release_doc(ttl=60)
        schema.check_time(doc, NOW + timedelta(minutes=10), 120)
        with self.assertRaisesRegex(schema.ApprovalError, "expired"):
            schema.check_time(doc, NOW + timedelta(minutes=61), 120)
        with self.assertRaisesRegex(schema.ApprovalError, "future"):
            schema.check_time(doc, NOW - timedelta(minutes=30), 120)
        with self.assertRaisesRegex(schema.ApprovalError, "maximum"):
            schema.check_time(self.release_doc(ttl=600), NOW, 120)


# =============================================================================== gate
class GateTests(unittest.TestCase):
    def test_allowed(self):
        self.assertEqual(deploy_gate.parse("status"), ["status"])
        self.assertEqual(deploy_gate.parse("history"), ["history", "20"])
        self.assertEqual(deploy_gate.parse(f"upload {RELEASE}"), ["upload", RELEASE])
        self.assertEqual(deploy_gate.parse("deploy " + "a" * 32), ["deploy", "a" * 32])

    def test_refused(self):
        for cmd in (None, "", "bash", "sh -i", "status; id", "status && id", "status|id", "$(id)", "`id`",
                    "upload ../../etc/passwd", "upload /etc/passwd", f"upload {RELEASE} extra", "deploy ABC",
                    "deploy " + "g" * 32, "history 999", "history -1", "status 'x'", 'status "x"',
                    "status\nid", "scp -t /tmp", "rsync --server", "x" * 300, "cancel", "rollback ../x"):
            with self.subTest(cmd=cmd), self.assertRaises(deploy_gate.Refused):
                deploy_gate.parse(cmd)


# =============================================================================== approvals
class ApprovalTests(Base):
    def test_valid_approval_is_stored_active(self):
        doc = self.release_doc()
        self.assertEqual(self.submit(doc), 0)
        self.assertEqual(self.record(doc["approval_id"])["status"], "active")
        audit = (Path(self.cfg.state_dir) / "audit.log").read_text()
        self.assertIn('"verb": "submit-approval"', audit)

    def test_signature_from_other_key_refused(self):
        with self.assertRaisesRegex(broker_mod.Refused, "signature"):
            self.submit(self.release_doc(), key=self.intruder)

    def test_wrong_namespace_refused(self):
        with self.assertRaisesRegex(broker_mod.Refused, "signature"):
            self.submit(self.release_doc(), namespace="file")

    def test_tampered_document_refused(self):
        env = json.loads(self.sign(self.release_doc()))
        doc = json.loads(base64.b64decode(env["document"]))
        doc["artifact_sha256"] = "1" * 64
        env["document"] = base64.b64encode(schema.canonical_bytes(doc)).decode()
        with self.assertRaisesRegex(broker_mod.Refused, "signature"):
            self.broker(json.dumps(env).encode()).cmd_submit_approval()

    def test_wrong_environment_refused(self):
        with self.assertRaisesRegex(broker_mod.Refused, "environment"):
            self.submit(self.release_doc(env="staging"))

    def test_expired_refused(self):
        with self.assertRaisesRegex(schema.ApprovalError, "expired"):
            self.submit(self.release_doc(issued=NOW - timedelta(hours=3)))

    def test_ttl_above_server_maximum_refused(self):
        with self.assertRaisesRegex(schema.ApprovalError, "maximum"):
            self.submit(self.release_doc(ttl=24 * 60))

    def test_malformed_envelope_refused(self):
        for raw in (b"", b"{}", b"[]", b'{"document":"!!","signature":"x"}', b"x" * 40000):
            with self.subTest(raw=raw[:20]), self.assertRaises(broker_mod.Refused):
                self.broker(raw).cmd_submit_approval()

    def test_replay_and_reuse(self):
        doc = self.release_doc()
        self.submit(doc)
        self.assertEqual(self.submit(doc), 0)  # identical resubmission of an ACTIVE approval is a no-op
        other = dict(doc, operations=["stage"])
        with self.assertRaisesRegex(broker_mod.Refused, "already used"):
            self.submit(other)
        rec = self.record(doc["approval_id"])
        rec["status"] = "consumed"
        (Path(self.cfg.state_dir) / "approvals" / f"{doc['approval_id']}.json").write_text(json.dumps(rec))
        with self.assertRaisesRegex(broker_mod.Refused, "replay refused"):
            self.submit(doc)

    def test_revocation(self):
        doc = self.release_doc()
        self.submit(doc)
        rev = {"version": 1, "type": "revocation", "approval_id": os.urandom(16).hex(), "environment": "production",
               "revokes": doc["approval_id"], "issued_at": schema.format_time(NOW),
               "expires_at": schema.format_time(NOW + timedelta(minutes=10))}
        self.submit(rev)
        self.assertEqual(self.record(doc["approval_id"])["status"], "revoked")
        with self.assertRaisesRegex(broker_mod.Refused, "revoked"):
            self.broker().cmd_deploy(doc["approval_id"])

    def test_pre_revoked_id_cannot_be_submitted_later(self):
        doc = self.release_doc()
        rev = {"version": 1, "type": "revocation", "approval_id": os.urandom(16).hex(), "environment": "production",
               "revokes": doc["approval_id"], "issued_at": schema.format_time(NOW),
               "expires_at": schema.format_time(NOW + timedelta(minutes=10))}
        self.submit(rev)
        with self.assertRaisesRegex(broker_mod.Refused, "revoked"):
            self.submit(doc)

    def test_unsigned_revocation_is_not_accepted(self):
        rev = {"version": 1, "type": "revocation", "approval_id": os.urandom(16).hex(), "environment": "production",
               "revokes": "a" * 32, "issued_at": schema.format_time(NOW),
               "expires_at": schema.format_time(NOW + timedelta(minutes=10))}
        with self.assertRaises(broker_mod.Refused):
            self.submit(rev, key=self.intruder)

    def test_executor_cancel(self):
        doc = self.release_doc()
        self.submit(doc)
        self.assertEqual(self.broker().cmd_cancel(doc["approval_id"]), 0)
        with self.assertRaisesRegex(broker_mod.Refused, "cancelled"):
            self.broker().cmd_deploy(doc["approval_id"])

    def test_approval_expires_between_submit_and_use(self):
        doc = self.release_doc(ttl=10)
        self.submit(doc)
        self.now = NOW + timedelta(minutes=11)
        with self.assertRaisesRegex(schema.ApprovalError, "expired"):
            self.broker().cmd_deploy(doc["approval_id"])
        self.assertEqual(self.record(doc["approval_id"])["status"], "expired")

    def test_wrong_operation_type(self):
        doc = self.release_doc()
        self.submit(doc)
        with self.assertRaisesRegex(broker_mod.Refused, "needs web-rollback"):
            self.broker().cmd_rollback(doc["approval_id"])

    def test_unknown_approval(self):
        with self.assertRaisesRegex(broker_mod.Refused, "no such approval"):
            self.broker().cmd_deploy("f" * 32)


# =============================================================================== upload + staging
class UploadStageTests(Base):
    def test_upload_without_approval_refused(self):
        with self.assertRaisesRegex(broker_mod.Refused, "no active owner approval"):
            self.broker(b"data").cmd_upload(RELEASE)

    def test_wrong_hash_refused_and_cleaned(self):
        self.submit(self.release_doc(sha256="a" * 64))
        with self.assertRaisesRegex(broker_mod.Refused, "does not match"):
            self.broker(self.make_archive()).cmd_upload(RELEASE)
        self.assertEqual(list((Path(self.cfg.state_dir) / "artifacts").iterdir()), [])

    def test_three_bad_uploads_fail_the_approval(self):
        doc = self.release_doc(sha256="a" * 64)
        self.submit(doc)
        for _ in range(3):
            with self.assertRaises(broker_mod.Refused):
                self.broker(b"junk").cmd_upload(RELEASE)
        self.assertEqual(self.record(doc["approval_id"])["status"], "failed")

    def test_size_limit(self):
        self.cfg.max_artifact_mb = 1
        self.submit(self.release_doc())
        with self.assertRaisesRegex(broker_mod.Refused, "exceeds"):
            self.broker(b"x" * (2 * 1024 * 1024)).cmd_upload(RELEASE)
        self.assertEqual(list((Path(self.cfg.state_dir) / "artifacts").glob("*")), [])

    def test_two_active_approvals_for_one_release_refused(self):
        self.submit(self.release_doc())
        self.submit(self.release_doc())
        with self.assertRaisesRegex(broker_mod.Refused, "cancel all but one"):
            self.broker(b"x").cmd_upload(RELEASE)

    def test_correct_upload_and_stage(self):
        aid = self.approved_upload(self.make_archive())
        art = Path(self.cfg.state_dir) / "artifacts" / f"{RELEASE}.tar.gz"
        self.assertEqual(oct(art.stat().st_mode & 0o777), "0o600")
        b = self.broker()
        rec, doc = b.valid_approval(aid, "web-release")
        rel = b.stage(rec, doc)
        self.assertEqual((rel / ".deploy-approval").read_text().strip(), aid)
        self.assertEqual(oct((rel / ".env").stat().st_mode & 0o777), "0o600")
        self.assertNotIn("supersecretvalue", self.output.getvalue())
        self.assertEqual(list(self.s["rel_root"].glob(".staging-*")), [])

    def _stage_malicious(self, extra=None, release=RELEASE, archive=None):
        archive = archive or self.make_archive(extra=extra, release=release)
        aid = self.approved_upload(archive)
        b = self.broker()
        rec, doc = b.valid_approval(aid, "web-release")
        with self.assertRaises(broker_mod.Refused) as ctx:
            b.stage(rec, doc)
        self.assertFalse((self.s["rel_root"] / RELEASE).exists(), "nothing may be created on refusal")
        self.assertEqual(list(self.s["rel_root"].glob(".staging-*")), [], "staging must be cleaned")
        return str(ctx.exception)

    def test_malicious_archives(self):
        def member(name, kind=tarfile.REGTYPE, data=b"x", linkname="", mode=0o644):
            m = tarfile.TarInfo(name)
            m.type, m.mode, m.linkname = kind, mode, linkname
            m.size = len(data) if kind == tarfile.REGTYPE else 0
            return m, data if kind == tarfile.REGTYPE else None
        cases = {
            "traversal": [member(f"{RELEASE}/../../evil.txt")],
            "absolute": [member("/etc/evil.conf")],
            "outside top dir": [member("other/evil.txt")],
            "symlink": [member(f"{RELEASE}/frontend/build/web/link", tarfile.SYMTYPE, linkname="/etc/shadow")],
            "hardlink": [member(f"{RELEASE}/hard", tarfile.LNKTYPE, linkname="/etc/passwd")],
            "fifo": [member(f"{RELEASE}/fifo", tarfile.FIFOTYPE)],
            "setuid": [member(f"{RELEASE}/suid", mode=0o4755)],
            "backslash": [member(f"{RELEASE}\\..\\evil")],
        }
        for label, extra in cases.items():
            with self.subTest(label):
                self.tearDown()
                self.setUp()
                self._stage_malicious(extra=extra)
                self.assertFalse((self.tmp / "evil.txt").exists())

    def test_wrong_release_dir_in_archive(self):
        archive = self.make_archive(release="20261024-5b4bd33-other")
        self.assertIn("outside", self._stage_malicious(archive=archive))

    def test_unpacked_size_limit(self):
        self.cfg.max_unpacked_mb = 0
        self.assertIn("too large", self._stage_malicious())

    def test_wrong_commit_in_archive(self):
        archive = self.make_archive(commit="1" * 40)
        aid = self.approved_upload(archive)
        b = self.broker()
        rec, doc = b.valid_approval(aid, "web-release")
        with self.assertRaisesRegex(broker_mod.Refused, "RELEASE_COMMIT"):
            b.stage(rec, doc)

    def test_existing_directory_not_staged_by_this_approval(self):
        stubs.make_release_dir(self.s["rel_root"], RELEASE, "MANUAL", COMMIT)
        aid = self.approved_upload(self.make_archive())
        b = self.broker()
        rec, doc = b.valid_approval(aid, "web-release")
        with self.assertRaisesRegex(broker_mod.Refused, "not staged by approval"):
            b.stage(rec, doc)


# =============================================================================== deploy + rollback
class DeployTests(Base):
    def deploy(self, ops=None) -> tuple[int, str]:
        aid = self.approved_upload(self.make_archive(), ops=ops)
        rc = self.broker().cmd_deploy(aid)
        return rc, aid

    def test_success(self):
        rc, aid = self.deploy()
        self.assertEqual(rc, 0, self.output.getvalue())
        st = self.docker_state()
        self.assertTrue(st["working_dir"].endswith(RELEASE))
        self.assertEqual(st["others"], {"mushukistan-backend": "bbbbbbbbbbbb", "mushukistan-db": "dddddddddddd"})
        rec = self.record(aid)
        self.assertEqual(rec["status"], "consumed")
        self.assertEqual({k: v["result"] for k, v in rec["steps"].items()},
                         {"upload": "ok", "stage": "ok", "preflight": "ok", "backup": "ok", "activate": "ok"})
        self.assertIn("DEPLOYED AND VERIFIED", self.output.getvalue())
        self.assertEqual(list(Path(self.cfg.token_dir).iterdir()), [], "tokens must be deleted")

    def test_replay_after_success_refused(self):
        rc, aid = self.deploy()
        with self.assertRaisesRegex(broker_mod.Refused, "consumed"):
            self.broker().cmd_deploy(aid)

    def test_preflight_failure_changes_nothing(self):
        self.flag("preflight-fail")
        with self.assertRaisesRegex(broker_mod.Refused, "preflight failed"):
            self.deploy()
        self.assertTrue(self.docker_state()["working_dir"].endswith("old"))
        self.assertEqual(list(self.s["backups"].iterdir()), [], "no backup before a passing preflight")

    def test_tls_warning_is_fatal(self):
        self.flag("preflight-warn")
        with self.assertRaisesRegex(broker_mod.Refused, "renewal webroot"):
            self.deploy()

    def test_backup_failure_prevents_activation(self):
        self.flag("backup-fail")
        with self.assertRaisesRegex(broker_mod.Refused, "backup failed"):
            self.deploy()
        self.assertTrue(self.docker_state()["working_dir"].endswith("old"))

    def test_failure_before_switch(self):
        self.flag("fail-before-switch")
        rc, aid = self.deploy()
        self.assertEqual(rc, 1)
        self.assertIn("FAILED BEFORE ACTIVATION", self.output.getvalue())
        self.assertEqual(self.record(aid)["status"], "failed")
        self.assertTrue(self.docker_state()["working_dir"].endswith("old"))

    def test_smoke_failure_auto_rollback(self):
        self.flag("verify-fail", RELEASE)
        rc, aid = self.deploy()
        self.assertEqual(rc, 1)
        self.assertIn("RESULT: ROLLED BACK", self.output.getvalue())
        self.assertTrue(self.docker_state()["working_dir"].endswith("old"))
        self.assertEqual(self.record(aid)["steps"]["auto-rollback"]["result"], "ok")

    def test_smoke_failure_without_auto_rollback_then_approved_rollback(self):
        self.flag("verify-fail", RELEASE)
        rc, aid = self.deploy(ops=["stage", "backup", "activate"])
        self.assertIn("does not include auto-rollback", self.output.getvalue())
        self.assertTrue(self.docker_state()["working_dir"].endswith(RELEASE))
        # the release approval cannot be used to roll back
        with self.assertRaises(broker_mod.Refused):
            self.broker().cmd_rollback(aid)
        # rollback approval for a release that is NOT active is refused
        wrong = {"version": 1, "type": "web-rollback", "approval_id": os.urandom(16).hex(), "environment": "production",
                 "release": "20261024-5b4bd33-other", "operations": ["rollback"], "issued_at": schema.format_time(NOW),
                 "expires_at": schema.format_time(NOW + timedelta(minutes=30))}
        self.submit(wrong)
        with self.assertRaisesRegex(broker_mod.Refused, "currently runs"):
            self.broker().cmd_rollback(wrong["approval_id"])
        good = dict(wrong, approval_id=os.urandom(16).hex(), release=RELEASE)
        self.submit(good)
        self.assertEqual(self.broker().cmd_rollback(good["approval_id"]), 0, self.output.getvalue())
        self.assertTrue(self.docker_state()["working_dir"].endswith("old"))
        with self.assertRaisesRegex(broker_mod.Refused, "consumed"):
            self.broker().cmd_rollback(good["approval_id"])

    def test_missing_rollback_target_refused_before_change(self):
        self.flag("verify-fail", RELEASE)
        self.deploy(ops=["stage", "backup", "activate"])
        os.rename(self.s["active"], str(self.s["active"]) + ".moved")
        good = {"version": 1, "type": "web-rollback", "approval_id": os.urandom(16).hex(), "environment": "production",
                "release": RELEASE, "operations": ["rollback"], "issued_at": schema.format_time(NOW),
                "expires_at": schema.format_time(NOW + timedelta(minutes=30))}
        self.submit(good)
        with self.assertRaisesRegex(broker_mod.Refused, "rollback target"):
            self.broker().cmd_rollback(good["approval_id"])
        self.assertTrue(self.docker_state()["working_dir"].endswith(RELEASE))

    def test_stage_only_scope(self):
        rc, aid = self.deploy(ops=["stage"])
        self.assertEqual(rc, 0)
        self.assertIn("RESULT: STAGED", self.output.getvalue())
        self.assertTrue(self.docker_state()["working_dir"].endswith("old"))
        self.assertEqual(list(self.s["backups"].iterdir()), [])

    def test_interruption_recovery_and_cleanup(self):
        aid = self.approved_upload(self.make_archive())
        rec = self.record(aid)
        rec["status"], rec["step"] = "activating", "activate"
        (Path(self.cfg.state_dir) / "approvals" / f"{aid}.json").write_text(json.dumps(rec))
        (Path(self.cfg.state_dir) / "artifacts" / "x.tar.gz.partial").write_text("x")
        Path(self.cfg.token_dir, "abc.token").write_text("a" * 32)
        (self.s["rel_root"] / ".staging-x-1").mkdir()
        b = self.broker()
        b.lock()
        b.unlock()
        self.assertEqual(self.record(aid)["status"], "interrupted")
        self.assertEqual(list((Path(self.cfg.state_dir) / "artifacts").glob("*.partial")), [])
        self.assertEqual(list(Path(self.cfg.token_dir).iterdir()), [])
        self.assertEqual(list(self.s["rel_root"].glob(".staging-*")), [])
        with self.assertRaisesRegex(broker_mod.Refused, "interrupted"):
            self.broker().cmd_deploy(aid)

    def test_concurrent_operation_refused(self):
        b1 = self.broker()
        b1.lock()
        try:
            with self.assertRaisesRegex(broker_mod.Refused, "another deployment"):
                self.broker().lock()
        finally:
            b1.unlock()

    def test_outputs_and_audit_hold_no_secrets(self):
        self.deploy()
        text = self.output.getvalue() + (Path(self.cfg.state_dir) / "audit.log").read_text()
        self.assertNotIn("supersecretvalue", text)
        out = broker_mod.Out(io.StringIO())
        out("POSTGRES_PASSWORD=hunter2 and JWT_SECRET: abc")
        self.assertNotIn("hunter2", out.lines[0])
        self.assertNotIn("abc", out.lines[0])


# =============================================================================== shell token check
class TokenScriptTests(Base):
    def check(self, path: str, token_dir: Path) -> subprocess.CompletedProcess:
        return subprocess.run(["bash", "-c", f'. "{DEPLOY / "approval-token.sh"}"; check_approval_token "$1"', "_", path],
                              env={**os.environ, "APPROVAL_TOKEN_DIR": str(token_dir)}, capture_output=True, text=True)

    def test_token_rules(self):
        d = self.tmp / "tok"
        d.mkdir(mode=0o700)
        os.chmod(d, 0o700)
        good = d / "a.token"
        good.write_text("a" * 32)
        os.chmod(good, 0o600)
        self.assertEqual(self.check(str(good), d).stdout.strip(), "a" * 32)
        os.chmod(good, 0o644)
        self.assertNotEqual(self.check(str(good), d).returncode, 0, "group/world-readable token refused")
        os.chmod(good, 0o600)
        bad = d / "b.token"
        bad.write_text("not-an-id")
        os.chmod(bad, 0o600)
        self.assertNotEqual(self.check(str(bad), d).returncode, 0)
        link = d / "l.token"
        link.symlink_to(good)
        self.assertNotEqual(self.check(str(link), d).returncode, 0, "symlinked token refused")
        outside = self.tmp / "o.token"
        outside.write_text("a" * 32)
        os.chmod(outside, 0o600)
        self.assertNotEqual(self.check(str(outside), d).returncode, 0, "token outside the directory refused")
        self.assertNotEqual(self.check(str(d / ".." / "o.token"), d).returncode, 0)
        os.chmod(d, 0o755)
        self.assertNotEqual(self.check(str(good), d).returncode, 0, "token directory must be 0700")

    def test_scripts_still_require_tty_without_token(self):
        r = subprocess.run(["bash", str(DEPLOY / "backup-db.sh"), "--label", "x", "--execute"],
                           env={**os.environ, "DOCKER_BIN": "false"}, capture_output=True, text=True, stdin=subprocess.DEVNULL)
        self.assertNotEqual(r.returncode, 0)


# =============================================================================== operator CLI
class CliTests(Base):
    def test_ci_evaluation(self):
        req = ("A", "B")
        ok = {"check_runs": [{"name": "A", "status": "completed", "conclusion": "success", "started_at": "1"},
                             {"name": "B", "status": "completed", "conclusion": "success", "started_at": "1"}]}
        self.assertEqual(release_web.evaluate_check_runs(ok, req), [])
        pending = {"check_runs": [dict(ok["check_runs"][0]), {"name": "B", "status": "in_progress", "conclusion": None}]}
        self.assertTrue(any("pending" in p for p in release_web.evaluate_check_runs(pending, req)))
        missing = {"check_runs": ok["check_runs"][:1]}
        self.assertTrue(any("has not run" in p for p in release_web.evaluate_check_runs(missing, req)))
        failed = {"check_runs": [*ok["check_runs"], {"name": "C", "status": "completed", "conclusion": "failure"}]}
        self.assertTrue(any("failure" in p for p in release_web.evaluate_check_runs(failed, req)))
        rerun = {"check_runs": [{"name": "A", "status": "completed", "conclusion": "failure", "started_at": "1"},
                                {"name": "A", "status": "completed", "conclusion": "success", "started_at": "2"},
                                ok["check_runs"][1]]}
        self.assertEqual(release_web.evaluate_check_runs(rerun, req), [], "a successful re-run supersedes")

    def test_unprotected_key_is_refused(self):
        safe, why = release_web.key_is_safe(self.owner)
        self.assertFalse(safe)
        self.assertIn("no passphrase", why)
        protected = self.tmp / "protected"
        subprocess.run(["ssh-keygen", "-q", "-t", "ed25519", "-N", "correct horse", "-f", str(protected)], check=True)
        self.assertTrue(release_web.key_is_safe(protected)[0])
        sk = self.tmp / "fido"
        sk.write_text("handle")
        Path(str(sk) + ".pub").write_text("sk-ssh-ed25519@openssh.com AAAA test\n")
        self.assertTrue(release_web.key_is_safe(sk)[0])

    def test_envelope_roundtrip(self):
        doc = self.release_doc()
        path = self.tmp / "d.json"
        path.write_bytes(schema.canonical_bytes(doc))
        subprocess.run(["ssh-keygen", "-q", "-Y", "sign", "-f", str(self.owner), "-n", schema.NAMESPACE, str(path)],
                       check=True, capture_output=True)
        env = release_web.envelope(path)
        self.assertEqual(self.broker(env).cmd_submit_approval(), 0)

    def test_owner_commands_need_a_terminal(self):
        with self.assertRaisesRegex(release_web.CliError, "interactive terminal"):
            release_web.require_owner_terminal()


# =============================================================================== review regressions
class ReviewRegressionTests(Base):
    """Findings of the pre-installation security review (docs/DEPLOYMENT_AUTOMATION.md, section 8)."""

    def staged(self, archive: bytes):
        aid = self.approved_upload(archive)
        b = self.broker()
        rec, doc = b.valid_approval(aid, "web-release")
        return aid, b, rec, doc

    def test_source_verified_and_crlf_tolerated(self):
        def crlf(d):
            (d / "docker-compose.yml").write_bytes(b"services: {}\r\n")
        aid, b, rec, doc = self.staged(self.make_archive(mutate=crlf))
        b.stage(rec, doc)
        self.assertIn("source verified: 2 files", self.output.getvalue())

    def test_tampered_compose_file_refused_and_removed(self):
        def evil(d):
            (d / "docker-compose.prod.yml").write_text("services: {nginx: {privileged: true}}\n")
        aid, b, rec, doc = self.staged(self.make_archive(mutate=evil))
        with self.assertRaisesRegex(broker_mod.Refused, "tampered build"):
            b.stage(rec, doc)
        self.assertFalse((self.s["rel_root"] / RELEASE).exists(), "unverified release directory must be removed")
        self.assertEqual(self.record(aid)["status"], "failed")
        self.assertIn("docker-compose.prod.yml: differs", self.output.getvalue())

    def test_extra_file_outside_build_outputs_refused(self):
        aid, b, rec, doc = self.staged(self.make_archive(mutate=lambda d: (d / "evil.sh").write_text("id")))
        with self.assertRaisesRegex(broker_mod.Refused, "tampered build"):
            b.stage(rec, doc)
        self.assertIn("evil.sh: not part of commit", self.output.getvalue())

    def test_missing_source_file_refused(self):
        aid, b, rec, doc = self.staged(self.make_archive(mutate=lambda d: (d / "docker-compose.yml").unlink()))
        with self.assertRaisesRegex(broker_mod.Refused, "tampered build"):
            b.stage(rec, doc)

    def test_build_outputs_may_differ_from_source(self):
        def more_web(d):
            (d / "frontend/build/web/extra.js").write_text("// built")
        aid, b, rec, doc = self.staged(self.make_archive(mutate=more_web))
        b.stage(rec, doc)

    def test_source_unavailable_is_transient(self):
        aid, b, rec, doc = self.staged(self.make_archive())
        (self.tmp / "src" / f"{COMMIT}.tar.gz").unlink()
        with self.assertRaises(broker_mod.SourceUnavailable):
            b.stage(rec, doc)
        self.assertEqual(self.record(aid)["status"], "active")
        self.assertFalse((self.s["rel_root"] / RELEASE).exists())

    def test_server_managed_files_in_archive_refused(self):
        def member(name):
            m = tarfile.TarInfo(name)
            m.size = 1
            return m, b"x"
        for name in (".env", "PREVIOUS_STATE.txt", ".deploy-approval", "docker-compose.notification-release.yml",
                     "backend/.env"):
            with self.subTest(name):
                self.tearDown()
                self.setUp()
                aid, b, rec, doc = self.staged(self.make_archive(extra=[member(f"{RELEASE}/{name}")]))
                with self.assertRaisesRegex(broker_mod.Refused, "server-managed"):
                    b.stage(rec, doc)

    def test_trailing_newline_identifiers_rejected(self):
        with self.assertRaises(schema.ApprovalError):
            schema.validate_approval_id("a" * 32 + "\n")
        with self.assertRaises(schema.ApprovalError):
            schema.validate_release_name(RELEASE + "\n")
        doc = self.release_doc()
        doc["commit"] = COMMIT + "\n"
        with self.assertRaises(schema.ApprovalError):
            schema.parse_document(schema.canonical_bytes(doc))
        with self.assertRaises(deploy_gate.Refused):
            deploy_gate.parse("history 20\n5")

    def test_silent_hung_command_is_killed(self):
        self.cfg.command_timeout = 2
        start = __import__("time").monotonic()
        rc, lines = self.broker().run(["bash", "-c", "sleep 60"])
        self.assertLess(__import__("time").monotonic() - start, 20)
        self.assertEqual(rc, 124)
        self.assertIn("timed out", lines[-1])

    def test_low_disk_space_refuses_upload(self):
        self.cfg.min_free_mb = 10 ** 9
        self.submit(self.release_doc())
        with self.assertRaisesRegex(broker_mod.Refused, "MB free"):
            self.broker(b"x").cmd_upload(RELEASE)

    def test_unexpected_error_after_switch_rolls_back(self):
        aid = self.approved_upload(self.make_archive())
        b = self.broker()
        calls = {"n": 0}
        real = b.other_container_ids

        def flaky():
            calls["n"] += 1
            if calls["n"] == 2:  # right after the activation script switched Nginx
                raise RuntimeError("docker daemon went away")
            return real()
        b.other_container_ids = flaky
        with self.assertRaisesRegex(RuntimeError, "went away"):
            b.cmd_deploy(aid)
        self.assertIn("RESULT: ROLLED BACK", self.output.getvalue())
        self.assertTrue(self.docker_state()["working_dir"].endswith("old"))
        self.assertEqual(self.record(aid)["status"], "failed")

    def test_dispatch_reports_unexpected_errors(self):
        aid = self.approved_upload(self.make_archive())
        b = self.broker()
        b.backup = lambda rec, doc: (_ for _ in ()).throw(OSError(28, "No space left on device"))
        self.assertEqual(b.dispatch("deploy", [aid]), 3)
        self.assertIn("unexpected failure", self.output.getvalue())
        self.assertIn('"result": "error"', (Path(self.cfg.state_dir) / "audit.log").read_text())
        self.assertTrue(self.docker_state()["working_dir"].endswith("old"))

    def test_missing_nginx_container_gives_emergency_guidance(self):
        self.s["env"]["STUB_NO_NGINX"] = "1"
        with self.assertRaisesRegex(broker_mod.Refused, "emergency procedure"):
            self.broker().active_deployment()


# =============================================================================== upload reliability
class UploadReliabilityTests(Base):
    """The first production rehearsal (2026-10-28): a dropped connection left the broker blocked
    on stdin, holding the deployment lock, until TCP keepalive gave up about two hours later."""

    def pipe_broker(self):
        """A broker whose stdin is a real pipe (like sshd provides), plus the writing end."""
        r, w = os.pipe()
        self.output = io.StringIO()
        reader = os.fdopen(r, "rb", buffering=0)
        self.addCleanup(reader.close)
        b = broker_mod.Broker(self.cfg, stdin=reader, out=broker_mod.Out(self.output), now=lambda: self.now)
        return b, os.fdopen(w, "wb", buffering=0)

    def unlocked(self) -> None:
        """Taking the lock succeeds, i.e. the failed operation released it."""
        b = self.broker()
        b.lock()
        b.unlock()

    def artifacts(self) -> list:
        return list((Path(self.cfg.state_dir) / "artifacts").iterdir())

    def test_stalled_upload_is_abandoned_cleaned_and_unlocked(self):
        import time
        self.cfg.upload_idle_timeout = 1
        archive = self.make_archive()
        import hashlib
        doc = self.release_doc(sha256=hashlib.sha256(archive).hexdigest(), ops=["stage"])
        self.submit(doc)
        b, writer = self.pipe_broker()
        writer.write(archive[:300])             # some bytes, then silence; the writer stays open
        start = time.monotonic()
        with self.assertRaisesRegex(broker_mod.Refused, r"upload stalled: no data for 1 s after 300 bytes"):
            b.dispatch("upload", [RELEASE])
        self.assertLess(time.monotonic() - start, 10)
        writer.close()
        self.assertEqual(self.artifacts(), [], "partial upload deleted")
        self.unlocked()                           # the deployment lock was released
        rec = self.record(doc["approval_id"])
        self.assertEqual(rec["status"], "active", "a network failure does not burn the approval")
        self.assertEqual(rec["steps"]["upload"]["result"], "interrupted")
        self.assertEqual(rec.get("upload_failures", 0), 0)
        self.assertEqual(self.broker(archive).cmd_upload(RELEASE), 0, "the same approval can retry")

    def test_upload_longer_than_the_maximum_is_abandoned(self):
        import threading
        import time
        self.cfg.upload_idle_timeout, self.cfg.upload_max_seconds = 5, 2
        self.submit(self.release_doc(ops=["stage"]))
        b, writer = self.pipe_broker()

        def trickle():                            # always some progress, never finished
            try:
                for _ in range(40):
                    writer.write(b"x")
                    time.sleep(0.2)
            except OSError:
                pass
            finally:
                writer.close()
        t = threading.Thread(target=trickle, daemon=True)
        t.start()
        start = time.monotonic()
        with self.assertRaisesRegex(broker_mod.Refused, "exceeded the maximum of 2 s"):
            b.dispatch("upload", [RELEASE])
        self.assertLess(time.monotonic() - start, 6)
        self.assertEqual(self.artifacts(), [])
        self.unlocked()

    def test_truncated_upload_reports_size_and_allows_retry(self):
        archive = self.make_archive()
        import hashlib
        doc = self.release_doc(sha256=hashlib.sha256(archive).hexdigest(), ops=["stage"])
        self.submit(doc)
        half = archive[: len(archive) // 2]
        with self.assertRaisesRegex(broker_mod.Refused, rf"\({len(half)} bytes\) does not match"):
            self.broker(half).dispatch("upload", [RELEASE])
        self.assertEqual(self.artifacts(), [])
        self.assertEqual(self.record(doc["approval_id"])["status"], "active")
        self.assertEqual(self.broker(archive).cmd_upload(RELEASE), 0)

    def test_dispatch_releases_the_lock_after_any_upload_failure(self):
        self.cfg.max_artifact_mb = 1
        self.submit(self.release_doc(ops=["stage"]))
        for data in (b"x" * (2 * 1024 * 1024), b"wrong"):
            with self.assertRaises(broker_mod.Refused):
                self.broker(data).dispatch("upload", [RELEASE])
            self.unlocked()
            self.assertEqual(self.artifacts(), [])

    def test_expired_approval_does_not_block_a_new_one(self):
        archive = self.make_archive()
        import hashlib
        sha = hashlib.sha256(archive).hexdigest()
        old = self.release_doc(sha256=sha, ops=["stage"], ttl=10)
        self.submit(old)
        self.now = NOW + timedelta(minutes=20)
        new = self.release_doc(sha256=sha, ops=["stage"], issued=self.now, ttl=30)
        self.submit(new)
        self.assertEqual(self.broker(archive).cmd_upload(RELEASE), 0)
        self.assertEqual(self.record(old["approval_id"])["status"], "expired")
        self.assertEqual(self.record(new["approval_id"])["status"], "active")
        b = self.broker()
        b.cmd_approvals()
        self.assertRegex(self.output.getvalue(), rf"{old['approval_id']} .* expired")
        rc = self.broker().cmd_deploy(new["approval_id"])
        self.assertEqual(rc, 0)
        self.assertIn("RESULT: STAGED", self.output.getvalue())

    def test_only_an_expired_approval_means_no_approval(self):
        self.submit(self.release_doc(ops=["stage"], ttl=10))
        self.now = NOW + timedelta(minutes=11)
        with self.assertRaisesRegex(broker_mod.Refused, "no active owner approval"):
            self.broker(b"x").cmd_upload(RELEASE)

    def test_expired_but_unused_approval_is_listed_as_expired(self):
        doc = self.release_doc(ops=["stage"], ttl=10)
        self.submit(doc)
        self.now = NOW + timedelta(minutes=11)
        b = self.broker()
        b.cmd_approvals()
        self.assertRegex(self.output.getvalue(), rf"{doc['approval_id']} .* expired ")
        self.assertEqual(self.record(doc["approval_id"])["status"], "active", "listing changes nothing")

    def test_upload_limits_are_validated_in_the_config(self):
        conf = self.tmp / "broker.conf"
        conf.write_text("UPLOAD_IDLE_TIMEOUT=120\nUPLOAD_MAX_SECONDS=1800\n")
        cfg = broker_mod.Config.load(str(conf))
        self.assertEqual((cfg.upload_idle_timeout, cfg.upload_max_seconds), (120, 1800))
        for bad in ("UPLOAD_IDLE_TIMEOUT=0\n", "UPLOAD_IDLE_TIMEOUT=5\n", "UPLOAD_MAX_SECONDS=10\n",
                    "UPLOAD_MAX_SECONDS=999999\n"):
            conf.write_text(bad)
            with self.assertRaisesRegex(broker_mod.Refused, "upload_idle_timeout"):
                broker_mod.Config.load(str(conf))

    def test_installer_configures_ssh_keepalive(self):
        text = (AUTOMATION / "install-server.sh").read_text()
        self.assertIn("ClientAliveInterval 30", text)
        self.assertIn("ClientAliveCountMax 4", text)
        self.assertIn('"clientaliveinterval 30"', text, "the installer verifies the effective setting")


class CliUploadTests(Base):
    """Client side of the upload: binary-exact streaming, progress, bounded duration."""

    def setUp(self):
        super().setUp()
        self.saved = {k: getattr(release_web, k) for k in
                      ("ssh_argv", "UPLOAD_STALL_SECONDS", "UPLOAD_MAX_SECONDS", "PROGRESS_SECONDS")}

    def tearDown(self):
        for k, v in self.saved.items():
            setattr(release_web, k, v)
        super().tearDown()

    def fake_ssh(self, code: str) -> None:
        release_web.ssh_argv = lambda settings, *remote: [sys.executable, "-c", code]

    def test_ssh_options_bound_connect_and_keepalive(self):
        argv = self.saved["ssh_argv"]({"MUSHUKISTAN_DEPLOY_KEY": "k", "MUSHUKISTAN_DEPLOY_TARGET": "u@h"}, "status")
        joined = " ".join(argv)
        for opt in ("BatchMode=yes", "IdentitiesOnly=yes", "StrictHostKeyChecking=yes", "ConnectTimeout=20",
                    "ServerAliveInterval=30", "ServerAliveCountMax=4"):
            self.assertIn(opt, joined)
        self.assertEqual(argv[-2:], ["u@h", "status"])

    def test_upload_stream_is_binary_exact(self):
        import hashlib
        data = bytes(range(256)) * 4096 + b"\r\n\x1a\x00\n\r" * 1000   # CR/LF, Ctrl-Z, NUL
        f = self.tmp / "artifact.bin"
        f.write_bytes(data)
        self.fake_ssh("import sys, hashlib; d = sys.stdin.buffer.read(); print(hashlib.sha256(d).hexdigest(), len(d))")
        log: list[str] = []
        rc = release_web.remote({}, "upload", RELEASE, stdin_path=f, log=log)
        self.assertEqual(rc, 0)
        self.assertIn(f"{hashlib.sha256(data).hexdigest()} {len(data)}", log)
        self.assertIn(f"  upload sent {len(data)} of {len(data)} bytes", "\n".join(log))

    def test_stalled_transfer_is_stopped(self):
        import time
        release_web.UPLOAD_STALL_SECONDS = 1
        f = self.tmp / "big.bin"
        f.write_bytes(os.urandom(8 * 1024 * 1024))   # far more than a pipe buffer
        self.fake_ssh("import time; time.sleep(60)")   # never reads: like a dead connection
        log: list[str] = []
        start = time.monotonic()
        rc = release_web.remote({}, "upload", RELEASE, stdin_path=f, log=log)
        self.assertLess(time.monotonic() - start, 15)
        self.assertEqual(rc, 124)
        self.assertIn("STOPPED: upload stalled", "\n".join(log))

    def test_transfer_longer_than_the_maximum_is_stopped(self):
        import time
        release_web.UPLOAD_MAX_SECONDS, release_web.PROGRESS_SECONDS = 2, 0.5
        f = self.tmp / "big.bin"
        f.write_bytes(os.urandom(8 * 1024 * 1024))
        self.fake_ssh("import sys, time\nwhile sys.stdin.buffer.read(65536): time.sleep(0.1)")   # slow but moving
        log: list[str] = []
        start = time.monotonic()
        rc = release_web.remote({}, "upload", RELEASE, stdin_path=f, log=log)
        self.assertLess(time.monotonic() - start, 15)
        self.assertEqual(rc, 124)
        text = "\n".join(log)
        self.assertIn("STOPPED: upload exceeded 2 s", text)
        self.assertIn("upload progress:", text)

    def test_ssh_failure_exit_code_is_returned(self):
        f = self.tmp / "a.bin"
        f.write_bytes(b"x" * 1000)
        self.fake_ssh("import sys; sys.exit(255)")
        self.assertEqual(release_web.remote({}, "upload", RELEASE, stdin_path=f, log=[]), 255)

    def test_deploy_success_rules(self):
        full = ["stage", "backup", "activate", "auto-rollback"]
        ok = release_web.deploy_succeeded
        self.assertTrue(ok(0, "DEPLOYED AND VERIFIED", full))
        self.assertTrue(ok(0, "STAGED (approval did not include backup/activate)", ["stage"]))
        self.assertTrue(ok(0, "STAGED AND BACKED UP (approval did not include activate)", ["stage", "backup"]))
        self.assertFalse(ok(0, "STAGED (approval did not include backup/activate)", full))
        self.assertFalse(ok(1, "STAGED", ["stage"]))
        self.assertFalse(ok(0, "NOT COMPLETED", ["stage"]))
        self.assertFalse(ok(1, "ROLLED BACK", full))

    def test_stage_only_deploy_exits_zero(self):
        import argparse
        import hashlib
        archive = self.tmp / f"{RELEASE}.tar.gz"
        archive.write_bytes(self.make_archive())
        sha = hashlib.sha256(archive.read_bytes()).hexdigest()
        rdir = self.tmp / "automation"
        (rdir / "approvals").mkdir(parents=True)
        (rdir / f"{RELEASE}.plan.json").write_text(json.dumps(
            {"release": RELEASE, "commit": COMMIT, "artifact": str(archive), "artifact_sha256": sha,
             "worktree": str(self.tmp)}))
        doc = self.release_doc(sha256=sha, ops=["stage"])
        path = rdir / "approvals" / f"{RELEASE}.{doc['approval_id']}.json"
        path.write_bytes(schema.canonical_bytes(doc))
        subprocess.run(["ssh-keygen", "-q", "-Y", "sign", "-f", str(self.owner), "-n", schema.NAMESPACE, str(path)],
                       check=True, capture_output=True)
        calls = []

        def fake_remote(settings, *verb, stdin_path=None, stdin_bytes=None, log=None):
            calls.append(verb[0])
            if verb[0] == "deploy":
                log.append("RESULT: STAGED (approval did not include backup/activate)")
            return 0

        def no_bash(settings):
            raise AssertionError("local public verification must not run for a stage-only approval")
        saved = (release_web.release_dir, release_web.remote, release_web.find_bash)
        release_web.release_dir, release_web.remote, release_web.find_bash = (lambda: rdir), fake_remote, no_bash
        try:
            rc = release_web.cmd_deploy(argparse.Namespace(release=RELEASE, skip_local_verify=False), {})
        finally:
            release_web.release_dir, release_web.remote, release_web.find_bash = saved
        self.assertEqual(rc, 0)
        self.assertEqual(calls, ["submit-approval", "upload", "deploy"])
        self.assertIn("Result: STAGED", (rdir / f"{RELEASE}.report.md").read_text())


if __name__ == "__main__":
    unittest.main()
