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
   approval is never reused. The archive may not contain server-managed files (`.env` anywhere,
   the private overlay, `PREVIOUS_STATE.txt`, `.deploy-approval`). `RELEASE_COMMIT.txt` must equal
   the approved commit. **Source verification**: the broker downloads the approved commit from the
   public repository (`SOURCE_ARCHIVE_URL`, default `codeload.github.com`) and requires every
   staged file outside `frontend/build/web/` and `website/dist/` to be byte-identical to it (CRLF
   normalised, because `package-release.sh` may run with `core.autocrlf`), with no missing and no
   extra files (only `RELEASE_COMMIT.txt` / `RELEASE_MANIFEST.txt` are added by the packager). A
   mismatch removes the freshly staged directory and fails the approval; an unreachable source
   keeps the approval usable. Free space is checked before upload and extraction. `.env` and the
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
| Tampered build from a compromised operator machine (the executor builds the artifact the owner signs) | Server-side **source verification** against the approved commit on GitHub: Compose files, Nginx config and every script must equal `main`; only the two build-output directories are unverifiable. | tampered compose/Nginx/extra/missing files (unit); real 5b4bd33 artifact verified (712 files) and a one-line tamper refused; tampered Nginx config refused (e2e) |
| Hung or slow command holding the lock | every child runs with a hard timeout (`COMMAND_TIMEOUT`, default 30 min); its whole process group is killed. | silent `sleep` killed (unit) |
| Disk full / state directory unavailable | free-space checks before upload and staging; unexpected errors are caught, reported, audited when possible, and an activation that failed after the switch still triggers the approved auto-rollback. | unit (simulated `ENOSPC`, simulated Docker failure after the switch) |
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
| Unit and negative tests (schema, gate, approvals, signatures, replay, revocation, expiry, uploads, 10 malicious archives, server-managed files, source verification, staging, deploy orchestration incl. failures and auto-rollback, unexpected errors, timeouts, disk space, interruption recovery, cleanup, token rules, CLI CI gate and key check) | `bash scripts/deploy/automation/run_unit_tests.sh` (Alpine container, non-root) | **67/67 passed** |
| Disposable end-to-end on Alpine: real `install-server.sh`, sshd, sudo, restricted account, gate, broker, real `activate-web-release.sh`/`backup-db.sh`, real Docker Compose (Docker-in-Docker), escape attempts (shell, PTY, sftp, scp, TCP forwarding, client environment), operator CLI, uninstall, manual workflow afterwards | `bash scripts/deploy/automation/e2e_automation.sh` | **107/107 passed** |
| The same end-to-end test on **Ubuntu 24.04** with the distribution's own `sshd_config`, PAM and sudo defaults: OpenSSH 9.6p1 Ubuntu-3ubuntu13.20, sudo 1.9.15p5, Python 3.12.3, Compose 2.40.3 (the production versions) | `bash scripts/deploy/automation/e2e_ubuntu.sh` | **107/107 passed** |
| Real artifact `20261024-5b4bd33-feed-redesign` (789 files) extracted by the broker and source-verified against GitHub | ad hoc, Alpine container | 712 source files equal `5b4bd33` (CRLF tolerated); one-line Compose tamper refused |
| Existing offline script tests (+ syntax of new scripts, token refusals in the real scripts) | `bash scripts/deploy/test_deploy_scripts.sh` | **56/56 passed** |
| Existing manual-workflow rehearsal (typed confirmation path unchanged) | `bash scripts/deploy/e2e_disposable.sh` | **all passed** |
| Existing TLS script tests | `bash scripts/tls/test_tls_scripts.sh` | **28/28 passed** |
| Real `prepare` on Windows (origin/main + live GitHub CI + existing build, `--skip-build`) | `release-web prepare --sha 5b4bd33 --label feed-redesign --skip-build --worktree ...` | reproduced the deployed artifact SHA-256 `83a244e3...` |

**Not tested**: the real production host (only containers with its exact package versions);
systemd/socket-activated sshd (the containers run `sshd` directly; the installer's reload is
best-effort because sshd reads its configuration per connection); FIDO2 signing and whether
`ssh-keygen -Y verify` enforces user presence; the `prepare` path with a full Flutter build
through the CLI (the same build commands ran manually for this release); signing with the
Windows OpenSSH 9.5 client; a real power loss (simulated with `kill -9`).

## 6. Security limitations (read before installing)

1. **Resolved by owner (2026-10-28)** (section 9); kept for the record. **The owner's root SSH
   key on the operator workstation was usable non-interactively by any local process, including
   the agent** (it worked with `BatchMode=yes` during read-only inspection). While that is true, a
   compromised agent can bypass this whole system with root SSH. The automation only separates
   the roles while the owner's keys stay protected (passphrase and not loaded in ssh-agent, or a
   FIDO2 key). The same applies to the approval key.
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
   needs an owner-signed rollback (tested) or the manual runbook. If the power loss happens
   between removing the old and starting the new Nginx container, no Nginx container exists and
   the broker refuses to act (it cannot read the active release): use section 10.
9. The built web bundle (`frontend/build/web`, `website/dist`) cannot be verified against the
   source; a compromised build machine could still ship altered JavaScript to visitors (not root
   on the server). Building the web bundle in CI and approving the CI artifact would close this.
10. The approval tool (`release-web approve`) runs from the same workspace the agent can edit. A
   compromised agent could alter it to display one document and sign another. Mitigations: the
   signed document is short; check it before signing (`type` the `.json` it writes, or sign by hand,
   section 9.3); the server prints the accepted scope on submission and in `approvals`; source
   verification limits what a misleading hash can achieve.
11. Expiry is checked at the start of each command, not between the steps of one `deploy` run; a
   revocation cannot be submitted while a deployment holds the lock (it applies to later steps).
12. Uploaded artifacts are kept in `/var/lib/mushukistan-deploy/artifacts` (about 20 MB each); there
   is no pruning yet.

## 7. Installation plan (production; every step needs the owner's approval; NOT done)

0. **Complete the prerequisites in section 11 first**, above all the root key rotation in
   section 9 (Limitation 1). Create the approval key, preferably
   `ssh-keygen -t ed25519-sk -O verify-required -C mushukistan-owner-approval -f $env:USERPROFILE\.ssh\mushukistan_owner_approval_sk`
   (or `ssh-keygen -t ed25519 -a 100` with a passphrase). Never `ssh-add` it.
1. Create the executor key: `ssh-keygen -t ed25519 -C mushukistan-deploy -f $env:USERPROFILE\.ssh\mushukistan_deploy_ed25519`.
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

## 8. Security review before installation (2026-10-24)

Reviewed: the complete diff of `feature/secure-deployment-automation` against `main`, with
attempts to escape the restricted account (shell, chained/substituted commands, PTY, sftp, scp,
TCP forwarding, client environment variables, sudo, Docker socket, broker state, trusted files,
`.env`). Passing tests were not taken as proof: every finding below was reproduced first.

| # | Severity | Finding | Status |
| --- | --- | --- | --- |
| 1 | **Critical** (operational) | The owner's root SSH key on the operator machine was usable non-interactively, so any local process, including a compromised agent, has root on production regardless of this system. | **Resolved by owner (2026-10-28)** (section 9): passphrase-protected root keys, old key revoked. |
| 2 | **High** | The owner signs a hash of an artifact built on the executor's machine. A compromised builder could hide a malicious Compose file or Nginx config (root on the host) behind an owner-approved hash. | **Fixed**: server-side source verification against the approved commit on GitHub; unit + e2e tests; real artifact verified. Residual: built web bundle (Limitation 9). |
| 3 | Medium | The approval tool runs from an agent-writable workspace and could misrepresent what is signed. | **Documented** (Limitation 10, section 9.3); impact reduced by #2. |
| 4 | Medium | A child process that hung *silently* was never killed (the timeout was only checked when output arrived), holding the deployment lock indefinitely. | **Fixed**: hard timeout, process-group kill; unit test. |
| 5 | Medium | Unexpected errors (disk full, Docker failure) escaped the refusal handling: no guidance, no audit entry, and no auto-rollback if they happened after the switch. | **Fixed**: activation guard with approved auto-rollback, catch-all with audit, free-space checks; unit tests. |
| 6 | Medium | If no Nginx container exists (crash during the recreate), the broker cannot determine the active release and refuses everything. | **Documented**: clear refusal message pointing to section 10 (unit test); recovery is owner-operated. |
| 7 | Low | An archive could contain server-managed files (`.env`, overlay, `PREVIOUS_STATE.txt`, `.deploy-approval`). No exploit found (they were compared, overwritten or unpredictable), but the broker trusted their absence. | **Fixed**: refused at extraction; unit tests. |
| 8 | Low | Validation regexes used `$`, which also matches before a trailing newline (`release\n` would pass). | **Fixed**: `fullmatch` everywhere; unit tests. |
| 9 | Low | The broker imported its helper module before checking that it is root-owned. | **Fixed**: ownership check before import (verified: a non-root-owned copy refuses to start). |
| 10 | Low | `assert_trusted` followed a symlink only one level; system binaries were not checked. | **Fixed**: resolved path checked to `/`; `docker`, `ssh-keygen`, `bash`, `curl` included. |
| 11 | Low | The installer aborted after a failed `systemctl reload ssh` (socket activation on Ubuntu) with sudoers already installed; it did not check the *effective* sshd settings. | **Fixed**: best-effort reload; `sshd -T -C user=mushukistan-deploy` must show the forced command, no TTY, no forwarding and the root-owned key file, otherwise the snippet is removed. |
| 12 | Low | Test wrappers left Docker-in-Docker volumes behind (`docker rm -f` without `-v`), also in the older `e2e_disposable.sh`. | **Fixed** (`-v`); the 8 volumes left by this session were verified and removed. |
| 13 | Info | Ubuntu's `sshd_config` places `UsePAM`, `AcceptEnv`, `Subsystem` after the `Include`; a `Match` block in an included file could capture them. | **Verified harmless** on Ubuntu 24.04: `sshd -t` passes, other users keep their global settings, `AcceptEnv LANG LC_*` cannot reach the gate (`-I`, `env_reset`). |
| 14 | Info | Root parses attacker-influenced input (signature via `ssh-keygen`, tar headers via Python). | Accepted: inputs are size-limited, links/special files are refused before extraction, the archive must match an owner-approved hash. Optional hardening: run `ssh-keygen -Y verify` and tar parsing as an unprivileged user. |

Escape attempts that were refused (e2e, Alpine and Ubuntu): interactive shell, `bash`, `;`, `$( )`,
path arguments, PTY (`-tt`), sftp subsystem, scp upload, `-L` TCP forwarding (server replies
"administratively prohibited"), `SetEnv SSH_ORIGINAL_COMMAND=...`, `sudo -n /bin/sh`, `docker ps`,
reading the broker state, writing the broker or `allowed_signers`, reading production `.env`, a
group-writable trusted script, self-signed approvals, and an intruder key.

Operational failure scenarios:

| Scenario | Behaviour | Evidence |
| --- | --- | --- |
| Connection drops during activation | broker ignores SIGHUP and finishes; result in `approvals`/`history` | e2e |
| Server reboots during deployment | tokens vanish with `/run`; lock released; approval becomes `interrupted` on the next command; recover with an owner-signed rollback, or section 10 if Nginx is missing | e2e (`kill -9`) |
| Backup succeeds, activation fails before the switch | `FAILED BEFORE ACTIVATION`, nothing changed, backup kept | unit + e2e (preflight/bundle) |
| Activation succeeds, public verification fails or times out | auto-rollback if approved, otherwise stop and request a signed rollback | unit + e2e |
| Rollback fails | `ROLLBACK FAILED - inspect production immediately`; approval failed; section 10 | unit (missing target) |
| Approval expires during deployment | the running command completes; later commands are refused | unit |
| Second deployment submitted concurrently | refused by the lock | unit |
| State directory unavailable | broker refuses before any action; mid-run errors are caught and reported | unit |

Manual workflow: after `install-server.sh --uninstall --execute` the typed `BACKUP`/`ACTIVATE`
commands work unchanged, and Nginx, backend, worker, database, the database volume, release
directories, the ACME mount and the audit log are untouched (e2e, both distributions).

## 9. Owner-operated root SSH key rotation (do this first)

**Status: Resolved by owner (2026-10-28).**

The owner does every step; the agent must not read, copy or change private keys. Keep the current
root session open until step 6 succeeds, so a mistake can always be undone.

1. **Create a new key on the owner's machine**, outside the repository:
   - preferred (FIDO2, touch and PIN):
     `ssh-keygen -t ed25519-sk -O verify-required -O resident -C mushukistan-root-2026 -f $env:USERPROFILE\.ssh\mushukistan_root_sk`
   - otherwise: `ssh-keygen -t ed25519 -a 100 -C mushukistan-root-2026 -f $env:USERPROFILE\.ssh\mushukistan_root_ed25519` with a strong passphrase.
   Register a **second** FIDO2 key (or keep an offline passphrase key) as a spare.
2. **Keep it out of any agent**: do not `ssh-add` it; check `ssh-add -l` (Windows: the
   *OpenSSH Authentication Agent* service should be stopped/disabled unless you need it).
3. **Add the public key** with the existing session: append the `.pub` line to
   `/root/.ssh/authorized_keys` (do not remove anything yet); `chmod 600 /root/.ssh/authorized_keys`.
4. **Test the new key in a second terminal** while the first stays open:
   `ssh -i <new key> -o IdentitiesOnly=yes <ssh-target> 'echo ok'` (expect the touch/passphrase
   prompt). Point `~/.ssh/config` at the new key (`IdentityFile`, `IdentitiesOnly yes`).
5. **Remove the old key**: identify it with `ssh-keygen -lf /root/.ssh/authorized_keys` and delete
   only that line.
6. **Verify**: the new key works; the old one fails
   (`ssh -i <old key> -o IdentitiesOnly=yes -o BatchMode=yes <ssh-target> true` → `Permission denied`);
   a command without a touch/passphrase must no longer succeed.
7. Delete the old private key from the workstation (or move it to encrypted offline storage) and
   record the change (no key material) in `docs/private/PRODUCTION_STATE.md`.
8. Optional hardening after the automation works: `PermitRootLogin prohibit-password` is already
   effectively in force (no passwords); consider a named admin account with sudo instead of root.

### 9.1 The approval key

A separate key used only for signing approvals, never for SSH logins, registered only in
`/etc/mushukistan-deploy/allowed_signers` (namespace-restricted). Prefer a FIDO2 key with
`-O verify-required`; never load it into an agent; keep its passphrase only in your head or a
password manager.

### 9.2 Keeping approval credentials away from the executor

- A FIDO2 key needs a physical touch (and PIN): software on the machine cannot sign alone.
- A passphrase key must not be cached by `ssh-agent`, Windows' OpenSSH agent, Pageant or a password
  manager's SSH agent feature.
- Run `approve` in your own terminal window, not through the agent's `!` prefix.
- Never place the key, its passphrase or a signed-but-unused approval in the repository or the
  agent's working directories; signed approvals are harmless after expiry but should not linger.
- Strongest option: sign on a separate device (another computer or a separate Windows account)
  that the agent never runs on.

### 9.3 Signing by hand (independent of the repository's tools)

`release-web prepare` prints the plan; check the artifact SHA-256 and commit, then create the
document yourself and sign it with plain OpenSSH:

```powershell
notepad approval.json      # one line, canonical JSON (see "Approval documents"), new random approval_id
ssh-keygen -Y sign -f $env:USERPROFILE\.ssh\mushukistan_owner_approval_sk -n mushukistan-deploy-approval approval.json
```

## 10. Emergency access and rollback

- **Normal rollback**: owner `release-web approve-rollback <active release>`, then
  `release-web rollback <active release>`.
- **Automation unavailable or Nginx container missing**: as root (owner), run the `rollback=`
  command recorded in `/opt/mushukistan-releases/<active release>/PREVIOUS_STATE.txt` (or the
  newest release whose Nginx run was interrupted); it recreates only Nginx from the previous
  release. Then `bash scripts/deploy/verify-public.sh` and `check-tls.sh --server`.
- **Cut off the executor immediately**: delete its line from `/etc/mushukistan-deploy/authorized_keys`
  (takes effect for new connections), or `install-server.sh --uninstall --execute`.
- **Lost SSH access**: the hosting provider's recovery console (provider unverified; record it in
  the private state file) plus the spare FIDO2/offline key from section 9.
- Never delete release directories, backups or volumes during an incident.

## 11. Installation prerequisites (checklist)

- [x] Section 9 done: old root key removed, new root key protected, spare key registered
      (Resolved by owner, 2026-10-28).
- [ ] Approval key created (FIDO2 preferred), never in an agent, public key handed over.
- [ ] Deploy key created for the executor (agent-usable by design).
- [ ] This branch reviewed, merged, pushed; CI green; installer copied from that exact commit.
- [ ] Server can reach `codeload.github.com` over HTTPS (source verification).
- [ ] `sshd -t` and `sshd -T -C user=mushukistan-deploy,...` checked by the installer; manual check
      that root login still works in a second terminal before closing the first.
- [ ] Recovery console access confirmed.
- [ ] Rehearsal with `approve --stage-only` (section 7, step 7).
