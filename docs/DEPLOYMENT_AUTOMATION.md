# Approval-based web deployment (design, implementation, installation plan)

**Status: implemented and tested locally and in a disposable Docker environment. NOT installed on
production.** Nothing in this document is active until the owner approves and performs the
installation in "Installation plan". Until then `docs/DEPLOYMENT.md` (manual gates G0-G6) is the
only deployment procedure.

Goal: **the owner approves a release; the automation executes it.** The server, not the agent's
instructions or local permission prompts, enforces that only an owner-approved artifact can be
staged, backed up, activated or rolled back, and only within the approved scope and time.

Scope of the first version: **web releases only** (Flutter web + landing + Nginx config), i.e.
procedure A of `docs/DEPLOYMENT.md`. Backend/worker releases (procedure B), database migrations
(G5) and Android stay manual and separately approved.

## 1. Architecture

```
 operator machine (Windows)                          production server (Linux)
 ┌─────────────────────────────────┐                ┌──────────────────────────────────────────────┐
 │ release-web prepare  (agent ok) │                │ sshd  Match User mushukistan-deploy           │
 │   origin/main + CI gate, build, │                │   ForceCommand deploy-gate, no TTY/forwarding │
 │   package, SHA-256, plan        │                │        │ (runs as mushukistan-deploy)         │
 │                                 │                │        ▼                                      │
 │ release-web approve  (OWNER)    │                │ deploy-gate: fixed verbs, strict tokens       │
 │   FIDO2/passphrase key ─► .sig  │                │        │ sudo -n (one rule: the broker)       │
 │                                 │   deploy key   │        ▼                                      │
 │ release-web deploy   (agent ok) │ ─────────────► │ broker (root): verify signature (allowed_     │
 │   submit-approval, upload,      │  restricted    │   signers, root-owned) ─ scope ─ time ─ replay│
 │   deploy, report                │  SSH identity  │   upload ► hash check ► safe extract ► stage  │
 └─────────────────────────────────┘                │   trusted activate-web-release.sh (dry run)   │
                                                    │   trusted backup-db.sh (token) ► verify dump  │
                                                    │   trusted activate --execute (token) ► Nginx  │
                                                    │   verify ► auto-rollback (only if approved)   │
                                                    │   audit.log (append, no secrets)              │
                                                    └──────────────────────────────────────────────┘
```

Two identities:

| Identity | Holder | Can | Cannot |
| --- | --- | --- | --- |
| **Release approver** | owner; key `MUSHUKISTAN_APPROVAL_KEY` (FIDO2 `sk-ssh-ed25519` with touch, or passphrase; never in ssh-agent; outside the repository) | sign approval, rollback and revocation documents | nothing on the server by itself (the key is only in `allowed_signers`, restricted to the namespace `mushukistan-deploy-approval`) |
| **Deployment executor** | agent / CLI; key `MUSHUKISTAN_DEPLOY_KEY`; Unix account `mushukistan-deploy` | the 10 gate verbs; a production change only with a valid owner approval | open a shell, allocate a TTY, forward ports, run any other sudo command, use Docker, read broker state, `.env` files or backups, modify approvals, scripts, `allowed_signers`, sudoers or sshd config |

### Approval documents

Canonical JSON (sorted keys, no whitespace, ASCII), signed with
`ssh-keygen -Y sign -n mushukistan-deploy-approval` (`scripts/deploy/automation/approval_schema.py`):

```json
{"approval_id":"<32 hex>","artifact_sha256":"<64 hex>","commit":"<40 hex>","environment":"production",
 "expires_at":"2026-10-24T12:00:00Z","issued_at":"2026-10-24T10:00:00Z",
 "operations":["stage","backup","activate","auto-rollback"],"release":"20261024-5b4bd33-feed-redesign",
 "type":"web-release","version":1}
```

| Type | Binds | Operations |
| --- | --- | --- |
| `web-release` | exact commit, release name (its sha7 must equal the commit), artifact SHA-256, environment | non-empty subset of `stage`, `backup`, `activate`, `auto-rollback`; `stage` required, `activate` requires `backup`, `auto-rollback` requires `activate` |
| `web-rollback` | the release Nginx must **currently** run | exactly `["rollback"]`: back to the target recorded in that release's `PREVIOUS_STATE.txt` (no free choice of target) |
| `revocation` | another `approval_id` | revokes it (even before it was submitted) |

Server rules (`broker.py`): exact field set; signature verified against root-owned
`/etc/mushukistan-deploy/allowed_signers` for identity `mushukistan-owner` and the namespace;
environment equals the server's; lifetime ≤ `MAX_TTL_MINUTES` (default **120**: long enough for
prepare→deploy on a slow link, short enough that a leaked approval expires the same day);
`issued_at` at most 5 minutes in the future; every `approval_id` is accepted once and kept forever
(replay refused); state is re-verified (signature, scope, time, status) before **every** step;
an activation consumes the approval whatever its outcome.

### Server components (all root-owned, installed by `install-server.sh`)

| File | Role |
| --- | --- |
| `/usr/local/lib/mushukistan-deploy/deploy-gate` (`automation/deploy_gate.py`) | SSH forced command. Splits `SSH_ORIGINAL_COMMAND` on whitespace, every token must match `[A-Za-z0-9._-]{1,80}`, verb from a fixed list, per-verb argument regex, then `exec sudo -n -- broker ...`. Never a shell. |
| `/usr/local/lib/mushukistan-deploy/broker` (`automation/broker.py`) | Root broker; refuses unless itself, its module, `broker.conf`, `allowed_signers` and every script it runs (and their parent directories) are root-owned and not group/world-writable; Python ≥ 3.12; `flock` serialises changing operations; ignores SIGHUP so a dropped session cannot abort an activation midway. |
| `activate-web-release.sh`, `backup-db.sh`, `verify-public.sh`, `approval-token.sh` | **Trusted copies** used by the broker. Scripts inside an uploaded archive are never executed. |
| `/etc/mushukistan-deploy/{broker.conf,allowed_signers,authorized_keys}` | configuration; `authorized_keys` uses `restrict,command=...` and lives outside the deploy user's control |
| `/etc/sudoers.d/mushukistan-deploy` | `mushukistan-deploy ALL=(root) NOPASSWD: /usr/local/lib/mushukistan-deploy/broker`, `env_reset` (no wildcards; the broker validates its own arguments) |
| `/etc/ssh/sshd_config.d/60-mushukistan-deploy.conf` | `Match User mushukistan-deploy`: `ForceCommand`, `AuthorizedKeysFile`, publickey only, `PermitTTY no`, all forwarding off, `Match all` terminator |
| `/var/lib/mushukistan-deploy/` (0700) | approvals, artifacts (0600), `audit.log` (append-only JSON lines), lock |
| `/run/mushukistan-deploy/` (0700) | single-use approval tokens (see G3/G4 below) |

The deploy account is **not** in the `docker` group (that would be root-equivalent); only the
broker, as root, talks to Docker.

### What `deploy <approval-id>` does (fail-closed at every step)

1. Re-verify the approval (`active`, signature, type, environment, not expired, not revoked).
2. **Stage**: re-hash the stored artifact against the approval; safe extraction into a
   `.staging-*` temporary directory under the release root (refuses absolute paths, `..`, `\`,
   entries outside `<release>/`, symlinks, hard links, devices, FIFOs, setuid/setgid, more than
   1 GiB unpacked or 20 000 entries; extraction with Python's `data` filter; modes normalised;
   root-owned), then an atomic rename. A release directory that exists but was not staged by this
   approval is never reused. `RELEASE_COMMIT.txt` must equal the approved commit. `.env` and the
   private overlay are copied from the active Nginx working directory (owner and mode preserved,
   values never printed).
3. **Preflight**: the trusted `activate-web-release.sh <release>` dry run (bundle checks, `.env`
   key names, exact active Compose file set, `docker compose config`, `nginx -t` in a disposable
   container, TLS webroot check). Any of its TLS/`.env` warnings is **fatal** here (the manual path
   only warns).
4. **Backup** (if approved): trusted `backup-db.sh --execute --approval-token` → dump verified
   (`pg_restore --list` > 10 entries, inside the backup directory).
5. **Activate** (if approved): trusted `activate-web-release.sh --execute --backup-file <dump>
   --approval-token`, which recreates **only Nginx**, writes `PREVIOUS_STATE.txt` (now including
   `approval_id=`), checks mounts and container ids and runs `verify-public.sh` against the new
   bundle hash. Then the server-side TLS consistency check.
6. On a failed activation **after** the switch: if the approval includes `auto-rollback`, the
   broker recreates only Nginx from the recorded previous Compose working directory and file set
   (validated paths, no command string is executed), checks the mounts and verifies the previous
   bundle. Otherwise it stops and asks for an owner-signed `web-rollback`.
7. Audit entries for every submission, upload, stage, backup, activation, rollback, refusal and
   interruption.

## 2. Threat model

| Threat | Control | Tested |
| --- | --- | --- |
| Compromised agent / Claude Code process | It holds only the deploy key: no shell, no Docker, no general sudo; every change needs an owner signature it cannot produce. **Only true if the agent cannot use the owner's root SSH key or approval key** (see Limitations 1). | gate/sudo/docker/file-permission checks (e2e) |
| Theft of the deploy key | Same as above; worst case: deploy an artifact the owner already approved, inside its window; cancel approvals (denial of service only); fill the upload area up to `MAX_ARTIFACT_MB` per active approval. Revoke: remove the line from `/etc/mushukistan-deploy/authorized_keys` or `install-server.sh --uninstall`. | intruder key refused; uninstall removes access (e2e) |
| Self-approval by the executor | `allowed_signers` contains only the owner key with a namespace restriction; root-owned. | deploy-key-signed approval refused (e2e) |
| Activation of a different commit or artifact | Approval binds commit, release name (sha7) and artifact SHA-256; upload and staging re-hash; `RELEASE_COMMIT.txt` checked. | wrong hash, wrong commit, tampered document, wrong release dir (unit + e2e) |
| Archive replaced after approval | Hash checked at upload and again before extraction; artifacts dir is root-only. CLI refuses if the local artifact changed after prepare. | e2e "CLI refuses a tampered artifact" |
| Expired or replayed approval | `expires_at` ≤ 120 min after `issued_at`; ids stored forever; status machine (`active → consumed/failed/revoked/cancelled/expired/interrupted`); re-checked before every step. | unit + e2e |
| Forged CLI arguments / shell injection | gate token regex (no quotes, `;`, `$`, `|`, `/`, spaces inside tokens); fixed verbs; broker re-validates; subprocesses use argument lists, never a shell. | 24 refusal cases (unit), e2e chained/substitution/traversal |
| Malicious archive paths and links | safe extractor (see step 2). | 10 cases (unit), traversal + symlink with a valid approval (e2e) |
| Privilege escalation through Docker or sudo | no `docker` group; single sudoers command without wildcards, `env_reset`; broker runs `python3 -I` and resets `PATH`/environment for every child; trusted-file ownership check. | `sudo -n /bin/sh` refused, `docker ps` refused, group-writable script refused (e2e) |
| Modification of the backup or rollback target | backups dir root-only; rollback target only from `PREVIOUS_STATE.txt` written by the trusted script into a root-owned release dir; paths validated under the release root; release directories are never deleted. | missing target refused, rollback for a non-active release refused (unit + e2e) |
| Compromise of the approval channel | Owner key must be FIDO2 with touch (preferred) or passphrase-protected and never in ssh-agent; the CLI refuses an unprotected key; revocations; short TTL. A stolen *and* unlocked owner key defeats the scheme (by definition). | CLI key check (unit) |
| Accidental production deletion | no delete operation exists; no volume, database or backend container is touched; `--no-deps --no-build`; container ids compared. | containers unchanged after deploy, rollback, auto-rollback (e2e) |
| Secrets in logs | values of `.env` never read into output; output and audit pass a redaction filter for `*PASSWORD*`, `*SECRET*`, `*TOKEN*`, `*KEY*`... assignments. | secret value absent from output and audit (unit + e2e) |
| Interruption (dropped SSH, killed broker, crash) | SIGHUP ignored; lock released by the kernel; on the next locked operation stale tokens, partial uploads and staging directories are removed and an approval left `activating` becomes `interrupted` (refused; recover with an owner-signed rollback). | client disconnect completes; `kill -9` mid-activation → interrupted → approved rollback (e2e) |
| Concurrent operations | exclusive `flock`; second caller refused. | unit |

## 3. How the approval gates change (after installation)

| Gate | Manual workflow (unchanged fallback) | Approval-based workflow |
| --- | --- | --- |
| G0 build/package | local | `release-web prepare` (origin/main + required CI checks + build + package + plan). No server contact. |
| G1 inspection | root SSH, user-granted | `release-web status / health / tls / approvals / history` through the restricted account; no root SSH needed. |
| G2 upload/stage | user runs `scp` + extraction | covered by the signed `stage` operation; the executor uploads, the server verifies hash and stages. |
| G3 backup | user types `BACKUP <label>` | covered by the signed `backup` operation; the broker passes a **single-use root-owned token** (`/run/mushukistan-deploy/*.token`, mode 600, dir 700, deleted after use) instead of a typed phrase. No fake TTY, no scripted keystrokes. |
| G4 activation | user types `ACTIVATE <release>` | covered by the signed `activate` operation; same token mechanism; `PREVIOUS_STATE.txt` records the approval id. |
| G5 migration | manual, separate review | **not automated** (out of scope). |
| G6 rollback | user runs the printed command | automatic only if the approval includes `auto-rollback` and only for a failed verification after the switch; otherwise an owner-signed `web-rollback` + `release-web rollback`. |

The typed-confirmation path of both scripts is untouched (`--approval-token` is a separate
option), so the manual runbook remains valid and is the fallback whenever the automation is
unavailable or uninstalled.

## 4. CLI

```powershell
.\scripts\deploy\release-web.ps1 prepare --sha <sha> --label <label> --client-id-from-live   # agent or owner
.\scripts\deploy\release-web.ps1 approve <release>            # OWNER, own terminal; FIDO touch / passphrase
.\scripts\deploy\release-web.ps1 deploy <release>             # agent or owner: submit, upload, deploy, report
.\scripts\deploy\release-web.ps1 status | health | tls | approvals | history [N]
.\scripts\deploy\release-web.ps1 approve-rollback <release>   # OWNER
.\scripts\deploy\release-web.ps1 rollback <release>
.\scripts\deploy\release-web.ps1 revoke <approval-id>         # OWNER
.\scripts\deploy\release-web.ps1 cancel <approval-id>         # anyone holding the deploy key; only reduces rights
```

Options: `approve --no-auto-rollback`, `--stage-only` (dry rehearsal: stage + preflight, no
backup, no activation), `--ttl-minutes`; `prepare --skip-build --worktree <dir>` reuses a clean,
already built checkout; `--nginx-gate` adds the local disposable Nginx gate. `prepare` checks free
RAM (≥ 2.5 GB) and runs heavy steps one at a time. Files go to the gitignored
`release/automation/` (plans, signed approvals, deployment reports).

Settings (`scripts/deploy/local.env`, gitignored): `MUSHUKISTAN_DEPLOY_TARGET`,
`MUSHUKISTAN_DEPLOY_KEY`, `MUSHUKISTAN_APPROVAL_KEY`, `MUSHUKISTAN_ENVIRONMENT`.

## 5. Tests

| Suite | Command | Result (2026-10-24) |
| --- | --- | --- |
| Unit and negative tests (schema, gate, approvals, signatures, replay, revocation, expiry, uploads, 10 malicious archives, staging, deploy orchestration incl. failures and auto-rollback, interruption recovery, cleanup, token rules, CLI CI gate and key check) | `bash scripts/deploy/automation/run_unit_tests.sh` (Alpine container, non-root) | **54/54 passed** |
| Disposable end-to-end: real `install-server.sh`, sshd, sudo, restricted account, gate, broker, real `activate-web-release.sh`/`backup-db.sh`, real Docker Compose in Docker-in-Docker, operator CLI | `bash scripts/deploy/automation/e2e_automation.sh` | **86/86 passed** |
| Existing offline script tests (+ syntax of new scripts, token refusals in the real scripts) | `bash scripts/deploy/test_deploy_scripts.sh` | **56/56 passed** |
| Existing manual-workflow rehearsal (typed confirmation path unchanged) | `bash scripts/deploy/e2e_disposable.sh` | **all passed** |
| Existing TLS script tests | `bash scripts/tls/test_tls_scripts.sh` | **28/28 passed** |
| Real `prepare` on Windows (origin/main + live GitHub CI + existing build, `--skip-build`) | `release-web prepare --sha 5b4bd33 --label feed-redesign --skip-build --worktree ...` | reproduced the deployed artifact SHA-256 `83a244e3...` |

**Not tested**: the real Ubuntu 24.04 host (the e2e host is Alpine with OpenSSH 9.9, sudo,
Python 3.12); FIDO2 signing and whether `ssh-keygen -Y verify` enforces user presence; the
`prepare` path with a full Flutter build through the CLI (the same build commands ran manually
for this release); signing with the Windows OpenSSH 9.5 client.

## 6. Security limitations (read before installing)

1. **The owner's root SSH key on the operator workstation is currently usable by any local
   process, including the agent** (it was used non-interactively for read-only inspection). While
   that is true, a compromised agent can bypass this whole system with root SSH. The automation
   only separates the roles after the owner protects that key (passphrase and not loaded in
   ssh-agent, or a FIDO2 key) or stops using root SSH from this machine. The same applies to the
   approval key.
2. The server cannot see how the owner stores the approval key; the CLI refuses an unprotected
   key, but that check runs on the workstation.
3. Within its lifetime an approval lets the executor choose *when* to deploy (not *what*).
4. Root on the server is trusted (it can edit the broker, `allowed_signers` and the audit log).
   The audit log is local; nothing ships it off the host.
5. The broker trusts the Docker daemon and the trusted script copies; updating those scripts
   requires re-running the installer (owner).
6. Automatic rollback reacts to `verify-public.sh` (HTTP status, cache headers, bundle hash,
   legal pages). Visual/browser smoke tests stay with the operator after deployment and do not
   trigger an automatic rollback.
7. Replay protection depends on `/var/lib/mushukistan-deploy` persisting; if it is wiped, an old
   approval could be resubmitted until it expires (≤ 120 min).
8. A `kill -9`/power loss during the Nginx switch leaves the approval `interrupted`; recovery
   needs an owner-signed rollback (tested) or the manual runbook.

## 7. Installation plan (production; every step needs the owner's approval; NOT done)

0. **Protect the owner keys first** (Limitation 1): add a passphrase to the root SSH key and keep
   it out of ssh-agent, or switch to a FIDO2 key; create the approval key, preferably
   `ssh-keygen -t ed25519-sk -O verify-required -C mushukistan-owner-approval -f %USERPROFILE%\.ssh\mushukistan_owner_approval_sk`
   (or `ssh-keygen -t ed25519 -a 100` with a passphrase). Never `ssh-add` it.
1. Create the executor key: `ssh-keygen -t ed25519 -C mushukistan-deploy -f %USERPROFILE%\.ssh\mushukistan_deploy_ed25519`.
2. Review, merge and push this branch to `main`; CI green.
3. Copy the reviewed scripts to the server (owner):
   `git archive <main sha> scripts/deploy | ssh -t <ssh-target> 'mkdir -p /root/mushukistan-automation-<sha7> && tar -x -C /root/mushukistan-automation-<sha7>'`
   and the two public keys (`*.pub` only).
4. Dry run (owner): `bash /root/mushukistan-automation-<sha7>/scripts/deploy/automation/install-server.sh --owner-key owner_approval.pub --deploy-key deploy.pub`.
5. Install (owner): same with `--execute`. It validates sudoers with `visudo -c` and sshd with
   `sshd -t` before reloading ssh; existing sessions and root login are unaffected.
6. Verify (agent, read-only):
   `sshd -T -C user=mushukistan-deploy,host=x,addr=127.0.0.1 | grep -E 'forcecommand|permittty|allowtcpforwarding'`,
   `sudo -l -U mushukistan-deploy`, `id mushukistan-deploy` (no `docker`), and from the workstation
   `release-web status`, plus refusals of `ssh ... bash` and `ssh -tt ...`.
7. Safe rehearsal: `release-web prepare` for the current `main` with a new label, owner
   `approve --stage-only`, `release-web deploy`: stages a new directory and runs the preflight;
   no backup, no Nginx change.
8. First real use: the next web release with the full approval.
9. Revoke/uninstall at any time: remove the key line from `/etc/mushukistan-deploy/authorized_keys`
   (instant), or `install-server.sh --uninstall --execute` (removes sshd snippet, sudoers entry,
   key file; locks the account; keeps the audit log). The manual runbook keeps working.

After installation, update `docs/DEPLOYMENT.md` (fact status, gate table) and `CLAUDE.md` rule 6:
the agent may use the restricted deploy identity for read-only verbs and for operations covered
by a valid owner-signed approval; root SSH stays owner-only.
