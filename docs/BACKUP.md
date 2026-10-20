# Encrypted nightly database backups

**Status: prepared, NOT active.** Nothing is installed on the server, no schedule is enabled,
no key exists for production, and nothing is uploaded anywhere. Enabling it needs the owner's
approval of (1) the off-site destination and credentials, (2) who owns the encryption key.

## Design

| Piece | Where | Notes |
| --- | --- | --- |
| `scripts/backup/backup-nightly.sh` | server (root) | `pg_dump -Fc` piped straight into `age`; no plaintext dump on disk; new file `mushukistan-nightly-YYYYMMDDTHHMMSSZ.dump.age` (mode 0600) + `.sha256`; refuses without a public recipient key; refuses a private key on the server; lock against overlap; disk check (3x DB size); retention; optional off-site hook (disabled by default). |
| `scripts/backup/restore-check.sh` | operator machine | Decrypts with the owner's private identity and restores into a disposable local PostGIS container (no published ports, removed afterwards); prints Alembic revision and row counts. It cannot target production. |
| `infrastructure/backup/*.example` | templates | systemd service/timer, `backup.env`, recipients file. All inert `.example` files. |

Encryption: [age](https://github.com/FiloSottile/age). The server holds only the **public**
key, so a compromised server cannot decrypt old backups. The private identity is held by the
owner offline (password manager or hardware-backed storage). **Losing the identity makes every
backup unreadable**: keep at least two copies in different places.

Retention (defaults, configurable): keep every backup younger than 14 days (`KEEP_DAILY`) plus
Sunday backups younger than 8 weeks (`KEEP_WEEKLY`). The newest backup is never deleted. Only
files named `mushukistan-nightly-*.dump.age` (and their `.sha256`) in `BACKUP_DIR` are ever
removed; the manual `mushukistan-*.dump` files made by `scripts/deploy/backup-db.sh` are not
touched.

## Enabling it (after approval; run by the owner, not part of any release)

1. On the owner's machine: `age-keygen -o mushukistan-backup-identity.txt`. Store the identity
   safely. Copy only the line starting `age1...` to the server as
   `/etc/mushukistan/backup/age-recipients.txt` (mode 0644, owner root).
2. Install: `install -m 0750 scripts/backup/backup-nightly.sh /usr/local/sbin/mushukistan-backup`,
   copy the two `.example` unit files to `/etc/systemd/system/` without the `.example` suffix,
   `apt install age`, `systemctl daemon-reload`.
3. Dry run: `/usr/local/sbin/mushukistan-backup --dry-run`; then one real run by hand; copy the
   file to the workstation and run `restore-check.sh` on it (step below).
4. Only then `systemctl enable --now mushukistan-backup.timer`.
5. Off-site: write a small `OFFSITE_HOOK` program for the approved destination (it receives the
   path of the *encrypted* file only). Credentials for it are separate and must be write-only.

## Restore (always into a scratch database first)

```bash
# on the operator machine, with the file copied from the server (e.g. scp) and Docker + age installed
bash scripts/backup/restore-check.sh --file mushukistan-nightly-20261020T031500Z.dump.age \
  --identity ~/safe/mushukistan-backup-identity.txt
```

A real production restore (data loss only, the owner's decision): stop the backend and worker,
restore into a scratch database first and compare, then restore with `pg_restore --clean
--if-exists` into the production database **only with explicit approval**, restart, and verify.
Never delete the `mushukistan_postgres_data` volume.

Run a restore check at least quarterly, and after any change to the backup scripts or the key.

## Tests

`bash scripts/backup/test_backup_scripts.sh` (needs `age`; the integration part also needs Docker).
It covers encryption, no-plaintext, refusal cases, partial-file cleanup, retention, the off-site
hook, and a real PostGIS dump/restore round trip with a throwaway key.
