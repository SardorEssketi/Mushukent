"""Approval documents for approval-based Mushukistan deployments (shared by the server
broker and the operator CLI). Standard library only.

An approval is a small canonical JSON document signed by the OWNER with
`ssh-keygen -Y sign -n mushukistan-deploy-approval`. The server verifies the signature
against a root-owned allowed_signers file, so the deployment identity can submit an
approval but can never create or alter one.

Document types:
  web-release   stage / backup / activate / auto-rollback of one exact web artifact
  web-rollback  roll Nginx back FROM the named (currently active) release
  revocation    cancel a previously issued approval
"""
from __future__ import annotations

import json
import re
from datetime import datetime, timezone

NAMESPACE = "mushukistan-deploy-approval"
VERSION = 1
SKEW_SECONDS = 300  # tolerated clock difference between operator machine and server

APPROVAL_ID_RE = re.compile(r"^[0-9a-f]{32}$")
COMMIT_RE = re.compile(r"^[0-9a-f]{40}$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
# Same convention as package-release.sh: YYYYMMDD-<sha7>-<label>
RELEASE_RE = re.compile(r"^(?P<date>[0-9]{8})-(?P<sha7>[0-9a-f]{7})-(?P<label>[A-Za-z0-9._-]{1,40})$")
ENVIRONMENT_RE = re.compile(r"^[a-z][a-z0-9-]{1,31}$")
TIME_RE = re.compile(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")

RELEASE_OPERATIONS = ("stage", "backup", "activate", "auto-rollback")

FIELDS = {
    "web-release": {"version", "type", "approval_id", "environment", "release", "commit",
                    "artifact_sha256", "operations", "issued_at", "expires_at"},
    "web-rollback": {"version", "type", "approval_id", "environment", "release",
                     "operations", "issued_at", "expires_at"},
    "revocation": {"version", "type", "approval_id", "environment", "revokes",
                   "issued_at", "expires_at"},
}


class ApprovalError(ValueError):
    """The document is malformed, out of scope, or not valid at this time."""


def utc_now() -> datetime:
    return datetime.now(timezone.utc).replace(microsecond=0)


def format_time(value: datetime) -> str:
    return value.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def parse_time(value: object, field: str) -> datetime:
    if not isinstance(value, str) or not TIME_RE.match(value):
        raise ApprovalError(f"{field} must be UTC time like 2026-10-24T10:00:00Z")
    return datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)


def canonical_bytes(document: dict) -> bytes:
    """The exact bytes that are signed: sorted keys, no whitespace, ASCII only."""
    return json.dumps(document, sort_keys=True, separators=(",", ":"), ensure_ascii=True).encode("ascii")


def validate_release_name(name: object) -> str:
    if not isinstance(name, str) or not RELEASE_RE.match(name):
        raise ApprovalError("release must look like YYYYMMDD-<sha7>-<label>")
    return name


def validate_approval_id(value: object) -> str:
    if not isinstance(value, str) or not APPROVAL_ID_RE.match(value):
        raise ApprovalError("approval_id must be 32 lowercase hex characters")
    return value


def parse_document(raw: bytes) -> dict:
    """Parse and structurally validate a document. Time and scope are checked separately."""
    if len(raw) > 4096:
        raise ApprovalError("approval document is too large")
    try:
        doc = json.loads(raw.decode("ascii"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ApprovalError(f"approval document is not ASCII JSON: {exc}") from None
    if not isinstance(doc, dict):
        raise ApprovalError("approval document must be a JSON object")
    if canonical_bytes(doc) != raw:
        raise ApprovalError("approval document is not in canonical form")
    kind = doc.get("type")
    if kind not in FIELDS:
        raise ApprovalError(f"unknown approval type: {kind!r}")
    if set(doc) != FIELDS[kind]:
        raise ApprovalError(f"{kind} fields must be exactly {sorted(FIELDS[kind])}")
    if doc["version"] != VERSION:
        raise ApprovalError(f"unsupported approval version: {doc['version']!r}")
    validate_approval_id(doc["approval_id"])
    if not isinstance(doc["environment"], str) or not ENVIRONMENT_RE.match(doc["environment"]):
        raise ApprovalError("environment is invalid")
    issued = parse_time(doc["issued_at"], "issued_at")
    expires = parse_time(doc["expires_at"], "expires_at")
    if expires <= issued:
        raise ApprovalError("expires_at must be after issued_at")

    if kind == "web-release":
        name = validate_release_name(doc["release"])
        if not isinstance(doc["commit"], str) or not COMMIT_RE.match(doc["commit"]):
            raise ApprovalError("commit must be a full 40-character SHA")
        if RELEASE_RE.match(name).group("sha7") != doc["commit"][:7]:
            raise ApprovalError("release name does not match the commit")
        if not isinstance(doc["artifact_sha256"], str) or not SHA256_RE.match(doc["artifact_sha256"]):
            raise ApprovalError("artifact_sha256 must be 64 lowercase hex characters")
        ops = doc["operations"]
        if (not isinstance(ops, list) or not ops or len(set(ops)) != len(ops)
                or any(op not in RELEASE_OPERATIONS for op in ops)):
            raise ApprovalError(f"operations must be distinct values from {list(RELEASE_OPERATIONS)}")
        if "stage" not in ops:
            raise ApprovalError("a web-release approval must include stage")
        if "activate" in ops and "backup" not in ops:
            raise ApprovalError("activate requires backup")
        if "auto-rollback" in ops and "activate" not in ops:
            raise ApprovalError("auto-rollback requires activate")
    elif kind == "web-rollback":
        validate_release_name(doc["release"])
        if doc["operations"] != ["rollback"]:
            raise ApprovalError('web-rollback operations must be exactly ["rollback"]')
    else:
        validate_approval_id(doc["revokes"])
        if doc["revokes"] == doc["approval_id"]:
            raise ApprovalError("a revocation cannot revoke itself")
    return doc


def check_time(doc: dict, now: datetime, max_ttl_minutes: int) -> None:
    issued = parse_time(doc["issued_at"], "issued_at")
    expires = parse_time(doc["expires_at"], "expires_at")
    if (expires - issued).total_seconds() > max_ttl_minutes * 60:
        raise ApprovalError(f"approval lifetime exceeds the server maximum of {max_ttl_minutes} minutes")
    if (issued - now).total_seconds() > SKEW_SECONDS:
        raise ApprovalError("approval is issued in the future (check clocks)")
    if now >= expires:
        raise ApprovalError("approval has expired")


def new_release_document(*, approval_id: str, environment: str, release: str, commit: str,
                         artifact_sha256: str, operations: list[str], issued_at: datetime,
                         ttl_minutes: int) -> dict:
    from datetime import timedelta
    doc = {
        "version": VERSION, "type": "web-release", "approval_id": approval_id,
        "environment": environment, "release": release, "commit": commit,
        "artifact_sha256": artifact_sha256, "operations": operations,
        "issued_at": format_time(issued_at),
        "expires_at": format_time(issued_at + timedelta(minutes=ttl_minutes)),
    }
    parse_document(canonical_bytes(doc))
    return doc


def new_rollback_document(*, approval_id: str, environment: str, release: str,
                          issued_at: datetime, ttl_minutes: int) -> dict:
    from datetime import timedelta
    doc = {
        "version": VERSION, "type": "web-rollback", "approval_id": approval_id,
        "environment": environment, "release": release, "operations": ["rollback"],
        "issued_at": format_time(issued_at),
        "expires_at": format_time(issued_at + timedelta(minutes=ttl_minutes)),
    }
    parse_document(canonical_bytes(doc))
    return doc


def new_revocation_document(*, approval_id: str, environment: str, revokes: str,
                            issued_at: datetime, ttl_minutes: int) -> dict:
    from datetime import timedelta
    doc = {
        "version": VERSION, "type": "revocation", "approval_id": approval_id,
        "environment": environment, "revokes": revokes,
        "issued_at": format_time(issued_at),
        "expires_at": format_time(issued_at + timedelta(minutes=ttl_minutes)),
    }
    parse_document(canonical_bytes(doc))
    return doc
