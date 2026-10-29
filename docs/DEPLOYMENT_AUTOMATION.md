# Approval-based web deployment (design, implementation, installation plan)

**Status: INSTALLED on production (2026-10-29)** by the owner, from `main`; updated with the
upload reliability fixes (section 12). Day-to-day use: section 13 ("Operating runbook"). The
manual gates G0-G6 in `docs/DEPLOYMENT.md` remain the fallback.

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

### What `upload <release>` does

The artifact arrives on stdin and is written to a root-only `.partial` file while it is hashed;
only a file whose SHA-256 equals the active approval's is kept. The upload is abandoned when no
data arrives for `UPLOAD_IDLE_TIMEOUT` seconds (default 120) or the transfer exceeds
`UPLOAD_MAX_SECONDS` (default 1800). Every failure (stall, overrun, size limit, hash mismatch)
deletes the partial file, releases the deployment lock and reports how many bytes arrived. A
stall or overrun does not count against the approval (the same approval can retry); a hash
mismatch does (three fail it). The SSH server additionally probes the deploy account's
connections (`ClientAliveInterval 30`, `ClientAliveCountMax 4`), so a client that disappears
without closing the connection is dropped within about two minutes. Expired approvals are
ignored when looking for the release's approval, so a leftover one never blocks a fresh one.

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

`deploy` streams the artifact to ssh through a pipe in 256 KiB chunks and prints progress
(MB, %, KB/s) every 10 s. It stops by itself when ssh accepts no data for 120 s or the upload
takes longer than 1800 s (exit 124; the server deletes the partial file). ssh runs with
`ConnectTimeout=20`, `ServerAliveInterval=30` and `ServerAliveCountMax=4`. `deploy` exits 0 when
the server did everything the approval asked for: `RESULT: DEPLOYED...` for a full approval,
`RESULT: STAGED...` for a stage-only (or stage + backup) approval.

Options: `approve --no-auto-rollback`, `--stage-only` (dry rehearsal: stage + preflight, no
backup, no activation), `--ttl-minutes`; `prepare --skip-build --worktree <dir>` reuses a clean,
already built checkout; `--nginx-gate` adds the local disposable Nginx gate. `prepare` checks free
RAM (≥ 2.5 GB) and runs heavy steps one at a time. Files go to the gitignored
`release/automation/` (plans, signed approvals, deployment reports).

Settings (`scripts/deploy/local.env`, gitignored): `MUSHUKISTAN_DEPLOY_TARGET`,
`MUSHUKISTAN_DEPLOY_KEY`, `MUSHUKISTAN_APPROVAL_KEY`, `MUSHUKISTAN_ENVIRONMENT`.

## 5. Tests

| Suite | Command | Result (2026-10-29) |
| --- | --- | --- |
| Unit and negative tests (schema, gate, approvals, signatures, replay, revocation, expiry, uploads, 10 malicious archives, server-managed files, source verification, staging, deploy orchestration incl. failures and auto-rollback, unexpected errors, timeouts, disk space, interruption recovery, cleanup, token rules, CLI CI gate and key check; upload stall/overrun/truncation with cleanup and lock release, expired approvals, CLI binary-exact streaming, client stall/overrun stop, stage-only exit code) | `bash scripts/deploy/automation/run_unit_tests.sh` (Alpine container, non-root) | **83/83 passed** |
| Disposable end-to-end on Alpine: real `install-server.sh`, sshd, sudo, restricted account, gate, broker, real `activate-web-release.sh`/`backup-db.sh`, real Docker Compose (Docker-in-Docker), escape attempts (shell, PTY, sftp, scp, TCP forwarding, client environment), operator CLI, uninstall, manual workflow afterwards; sshd keepalive settings, a stalled upload over real SSH, CLI stage-only run | `bash scripts/deploy/automation/e2e_automation.sh` | **118/118 passed** |
| The same end-to-end test on **Ubuntu 24.04** with the distribution's own `sshd_config`, PAM and sudo defaults: OpenSSH 9.6p1 Ubuntu-3ubuntu13.20, sudo 1.9.15p5, Python 3.12.3, Compose 2.40.3 (the production versions) | `bash scripts/deploy/automation/e2e_ubuntu.sh` | **118/118 passed** |
| Windows OpenSSH 9.5p2 client (`ssh.exe`) streaming 22 MB of random bytes plus CR/LF, Ctrl-Z, NUL and 0xFF into a disposable local sshd: old file-handle stdin and new pipe both byte-exact; with the container frozen mid-transfer the CLI stopped after its stall limit (exit 124) | ad hoc, Windows host + Alpine container | **byte-exact; stall stopped** |
| Real artifact `20261024-5b4bd33-feed-redesign` (789 files) extracted by the broker and source-verified against GitHub | ad hoc, Alpine container | 712 source files equal `5b4bd33` (CRLF tolerated); one-line Compose tamper refused |
| Existing offline script tests (+ syntax of new scripts, token refusals in the real scripts) | `bash scripts/deploy/test_deploy_scripts.sh` | **56/56 passed** |
| Existing manual-workflow rehearsal (typed confirmation path unchanged) | `bash scripts/deploy/e2e_disposable.sh` | **all passed** |
| Existing TLS script tests | `bash scripts/tls/test_tls_scripts.sh` | **28/28 passed** |
| Real `prepare` on Windows (origin/main + live GitHub CI + existing build, `--skip-build`) | `release-web prepare --sha 5b4bd33 --label feed-redesign --skip-build --worktree ...` | reproduced the deployed artifact SHA-256 `83a244e3...` |

**Not tested**: the real production host (only containers with its exact package versions);
systemd/socket-activated sshd (the containers run `sshd` directly; the installer's reload is
best-effort because sshd reads its configuration per connection); FIDO2 signing and whether
`ssh-keygen -Y verify` enforces user presence; the `prepare` path with a full Flutter build
through the CLI (the same build commands ran manually for this release); a real power loss
(simulated with `kill -9`). Signing with the Windows OpenSSH 9.5 client was exercised by the
first production rehearsal (2026-10-28).

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
13. Upload bounds assume a usable link: with `UPLOAD_MAX_SECONDS=1800` a 21 MB artifact needs about
   12 KB/s on average. A slower link fails cleanly (nothing staged) and needs a better connection
   or a higher limit in `broker.conf` (owner, root).

## 7. Installation plan (production; owner-run; done 2026-10-29)

0. **Complete the prerequisites in section 11 first**, above all the root key rotation in
   section 9 (Limitation 1). Create the approval key, preferably
   `ssh-keygen -t ed25519-sk -O verify-required -C mushukistan-owner-approval -f $env:USERPROFILE\.ssh\mushukistan_owner_approval_sk`
   (or `ssh-keygen -t ed25519 -a 100` with a passphrase). Never `ssh-add` it.
1. Create the executor key: `ssh-keygen -t ed25519 -C mushukistan-deploy -f $env:USERPROFILE\.ssh\mushukistan_deploy_ed25519`.
2. Review, merge and push this branch to `main`; CI green.
3. Copy the reviewed scripts to the server (owner). Write the archive to a file first: Windows
   PowerShell 5.1 pipes native output as text and corrupts a binary stream piped into `ssh`.
   `git archive --format=tar -o mushukistan-automation-<sha7>.tar <main sha> scripts/deploy`, check
   its SHA-256, `scp` it with the two public keys (`*.pub` only) to `/root/`, and on the server
   `mkdir -p /root/mushukistan-automation-<sha7> && tar -xf mushukistan-automation-<sha7>.tar --no-same-owner -C /root/mushukistan-automation-<sha7>`.
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

To update the server-side automation later (for example after a fix like section 12), repeat
steps 3-6 from the new `main` commit with the same two public keys. `docs/DEPLOYMENT.md` and
`CLAUDE.md` rule 6 describe the installed state.

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
- [x] Approval key created (passphrase-protected Ed25519), never in an agent, public key handed over.
- [x] Deploy key created for the executor (agent-usable by design).
- [x] This branch reviewed, merged, pushed; CI green; installer copied from that exact commit.
- [ ] Server can reach `codeload.github.com` over HTTPS (source verification).
- [ ] `sshd -t` and `sshd -T -C user=mushukistan-deploy,...` checked by the installer; manual check
      that root login still works in a second terminal before closing the first.
- [x] Recovery console access confirmed.
- [ ] Rehearsal with `approve --stage-only` (section 7, step 7).

## 12. Upload reliability fixes (2026-10-29)

**Incident (first stage-only rehearsal, 2026-10-28).** The approval was accepted; the upload of a
21 MB artifact then lost its connection (`client_loop: send disconnect: Connection reset`, ssh exit
255). The server never saw the connection close and the broker kept waiting for data, holding
the deployment lock, until Linux TCP keepalive dropped the connection about two hours later. It
then hashed the incomplete file, refused it (SHA-256 mismatch), deleted it and released the lock.
Production was not changed. Root cause: no keepalive on the deploy account's SSH connections, no
idle or duration limit on the upload, and no client-side stall detection. Binary corruption was
ruled out (the file is never passed through a PowerShell pipeline; Windows OpenSSH streams it
byte-exact, section 5).

**Changes** (none affects approval verification, the forced command, sudo or the restrictions):

| Where | Change |
| --- | --- |
| `install-server.sh` (sshd snippet) | `ClientAliveInterval 30`, `ClientAliveCountMax 4` inside the `Match User mushukistan-deploy` block; the installer verifies both in the effective configuration. Other accounts unaffected. |
| `broker.py` | Upload idle timeout (`UPLOAD_IDLE_TIMEOUT`, default 120 s) and maximum duration (`UPLOAD_MAX_SECONDS`, default 1800 s), both validated; failures report the bytes received and keep the approval usable; expired approvals are ignored (and marked `expired`) when finding a release's approval and shown as `expired` in listings. |
| `broker.conf.example` | Documents the two new settings. Existing `broker.conf` files keep working: the defaults apply. |
| `release_web.py` | ssh `ConnectTimeout=20`, `ServerAliveCountMax=4`; upload streamed through a pipe with progress, stall stop (120 s) and maximum duration (1800 s); `deploy` exits 0 for `RESULT: STAGED` when the approval has no `activate`. |
| Tests | 16 unit tests and 11 end-to-end checks (section 5). |

**Server-side installation (owner, after merge; nothing else changes on the server).** Re-run the
installer from the merged `main` commit as in section 7, steps 3-5, with the same two public keys
(it rewrites `allowed_signers` and `authorized_keys` from them, replaces the broker and the
sshd snippet, and keeps `broker.conf`, the state directory and the audit log). Keep one root
session open until a new root login and `release-web status` both work. Verify (read-only):
`sshd -T -C user=mushukistan-deploy,host=x,addr=127.0.0.1 | grep -E '^clientalive'` prints
`clientaliveinterval 30` and `clientalivecountmax 4`. The client-side changes take effect as
soon as the operator runs `release-web` from the merged commit.

## 13. Operating runbook: web updates

Roles: the **agent** (or the owner) runs `release-web` with the deploy key from a checkout of
`main` that has `scripts/deploy/local.env`; the **owner** signs approvals in their own
PowerShell window and is the only one who uses root SSH. Commands below are run from the
repository root as `.\scripts\deploy\release-web.ps1 <verb>`.

Scope check first: only Flutter web, landing and Nginx-config changes go this way. Anything
touching the backend, the worker, the database or Android uses the manual procedures of
`docs/DEPLOYMENT.md`.

1. **Main is ready** (owner): the change is merged to `main`, pushed, CI green.
2. **Baseline** (agent): `status`, `health`, `tls`, `approvals`. Record the active release, the
   served `main.dart.js` hash and the container IDs. Cancel leftover active approvals
   (`cancel <id>`), which only removes rights.
3. **Prepare** (agent): `prepare --sha <main sha> --label <short-label> --client-id-from-live`.
   It checks CI, builds in a clean worktree (needs about 2.5 GB free RAM), packages and writes
   `release/automation/<release>.plan.json`. No server contact. Report the release name,
   commit, artifact SHA-256 and `main.dart.js` hash to the owner.
4. **Approve** (owner, own terminal, same checkout):
   `release-web approve <release>` for a full release (stage, backup, activate, auto-rollback),
   or `approve <release> --stage-only` for a rehearsal. Type `APPROVE <release>`, enter the key
   passphrase. The approval is valid for 120 minutes (`--ttl-minutes`).
5. **Deploy** (agent, after the owner's go-ahead for that commit):
   `deploy <release>`. It submits the approval, uploads the artifact with progress (about
   21 MB; use a stable connection) and runs the approved operations. Success is
   `RESULT: DEPLOYED ...` (exit 0) for a full release, `RESULT: STAGED ...` for a stage-only
   approval. The report is in `release/automation/<release>.report.md`.
6. **Verify** (agent): `status`, `health`, `tls`, `history 5`; the served `main.dart.js` matches
   the plan; all container IDs except Nginx are unchanged. Update the private state file
   (`docs/private/PRODUCTION_STATE.md`) and report each flow as VERIFIED, FAILED or NOT VERIFIED.

If something goes wrong:

| Symptom | Meaning and action |
| --- | --- |
| `STOPPED: upload stalled ...` / `upload exceeded ...` (exit 124), or ssh exit 255 during upload | Nothing was staged; the server deleted the partial file and released the lock. Rerun `deploy <release>` on a stable link while the approval is valid (a stall does not use it up). |
| `does not match the approved SHA-256` | The bytes differ from the plan. Three mismatches fail the approval; check the artifact, then a new owner approval. |
| `approval is expired` / `no active owner approval` | The owner signs a new approval (step 4). Expired ones are ignored automatically. |
| `another deployment operation is running` | Another operation holds the lock; wait (uploads are bounded to 30 min) and retry. Never kill processes on the server. |
| `preflight failed; nothing was changed` | Read the preflight output in the report; fix in the repository, prepare again. |
| Verification failed after activation | With `auto-rollback` approved the broker switched Nginx back already (`history` shows it). Otherwise: owner `approve-rollback <active release>`, agent `rollback <active release>`. |
| Automation unavailable | Section 10 (manual root rollback) and the manual procedure A of `docs/DEPLOYMENT.md`. |

Updating the automation itself (owner, root): section 7, steps 3-6, from the new `main` commit.
Revoking the executor: section 10.
