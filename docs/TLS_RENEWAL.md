# TLS certificate renewal (Let's Encrypt, certbot webroot)

**Status:** designed and tested in a disposable environment. The production switch needs the
owner's explicit approval (see "Production procedure"). Nothing in this file changes production
by itself.

## Root cause (found 2026-10-20)

The certificate lineage for `mushukistan.uz`, `www.mushukistan.uz` and `api.mushukistan.uz` was
issued with certbot's `standalone` authenticator. Standalone answers the HTTP-01 challenge by
binding TCP port 80 itself. Port 80 belongs to the Nginx container (Docker's proxy), so every
scheduled `certbot renew` fails with `Could not bind TCP port 80`. The stock `certbot.timer`
runs twice a day and has been failing since the 30-day renewal window opened; the certificate
expires **2026-11-09**. Nothing else is wrong: the public HTTP-01 path is routed correctly for
all three hostnames (the ACME location answers 404 for unknown tokens, only other paths redirect
to HTTPS), there is no CAA record and no firewall.

## Design

| Piece | Decision |
| --- | --- |
| Authenticator | `webroot`. No port is bound and **Nginx is never stopped**. |
| ACME webroot | A fixed host directory, `/var/www/certbot`, mounted read-only into Nginx at `/var/www/certbot` by `docker-compose.prod.yml` (was the release-relative `./infrastructure/certbot/www`). Certbot (host, root) writes challenge files; Nginx serves them from its existing `location /.well-known/acme-challenge/` on port 80, which is declared before the catch-all redirect, so the HTTP→HTTPS redirect cannot interfere. |
| Reload after renewal | A certbot **deploy hook** (`scripts/tls/reload-nginx.sh`, installed as `/etc/letsencrypt/renewal-hooks/deploy/mushukistan-reload-nginx.sh`) runs `nginx -t` and then `nginx -s reload` inside the running container. No restart, no recreate, no dropped connection. Certbot runs deploy hooks only after a successful renewal. |
| Scheduling | The existing `certbot.timer` (twice daily, `certbot -q renew`). Unchanged. |
| Certificate files | Nginx already mounts the whole `/etc/letsencrypt` read-only, so renewed files (symlinks into `archive/`) are visible to the container. |
| Persistence | The webroot is outside every release directory, and the compose file mounts it, so future releases keep it. `scripts/deploy/activate-web-release.sh` warns in its dry run (and after the switch) when certbot's webroot would differ from what the release mounts, and prints the fix. `scripts/tls/check-tls.sh` detects the same drift at any time. |
| Server-side scripts | Installed once under `/usr/local/lib/mushukistan-tls/` (root-owned, release-independent): `set-webroot.sh`, `check-tls.sh`, `reload-nginx.sh`. |

### Two phases, because a mount change needs a container recreate

Changing the ACME mount of the **running** Nginx container would require recreating it (a few
seconds of downtime). The renewal fix must not wait for, or cause, that. So:

1. **Now, zero downtime:** point certbot's webroot at the directory the running container
   *already* mounts (the active release's `infrastructure/certbot/www`, which is writable on the
   host). Install the hook. Nothing about Nginx changes.
2. **With the next normal release** (whose Nginx recreate is already planned and accepted): the
   release's `docker-compose.prod.yml` mounts `/var/www/certbot`. Right after activation run
   `set-webroot.sh /var/www/certbot --execute` (the activation script prints this exact command
   when it detects the difference). Between activation and that command, a renewal attempt would
   fail; renewals are attempted twice a day but are due only about every 60 days, so the window
   is minutes long and the checks flag it.

The same one-liner is the fix after **any** Nginx rollback to a release whose ACME mount differs
(`check-tls.sh --server` reports it and prints the command).

## Production procedure (each numbered step needs the owner's approval)

`<ssh-target>` is `bash scripts/deploy/ssh-target.sh`. `<A>` is the active ACME directory printed
by `check-tls.sh --server` (currently the active release's `infrastructure/certbot/www`).

1. **Read-only inspection** (done 2026-10-20): certbot version/config/timer/hooks, Nginx
   mounts, listeners, public HTTP-01 routing.
2. **Install the scripts** (adds three files; touches nothing running):
   `scp scripts/tls/{set-webroot,check-tls,reload-nginx}.sh <ssh-target>:/tmp/` then on the server
   `install -d -m 755 /usr/local/lib/mushukistan-tls && install -m 755 /tmp/{set-webroot,check-tls,reload-nginx}.sh /usr/local/lib/mushukistan-tls/`.
3. **Dry run** (read-only): `bash /usr/local/lib/mushukistan-tls/set-webroot.sh <A>` — verifies
   that Nginx serves `<A>` as the ACME directory, lists the hostnames, prints the plan.
4. **Apply** (owner types `TLS-WEBROOT <A>` in a real terminal):
   `ssh -t <ssh-target> bash /usr/local/lib/mushukistan-tls/set-webroot.sh <A> --execute`.
   Order of operations (every step is safe to abort): backup of the renewal config (private, 0600) to
   `/root/mushukistan-backups/tls/`; **validation 1**, `certbot certonly --dry-run --force-renewal`
   with the webroot method against the Let's Encrypt **staging** CA for all three hostnames (nothing is
   saved); deterministic rewrite of the lineage config (`authenticator = webroot`, `webroot_path`,
   `[[webroot_map]]`); **validation 2**, `certbot renew --cert-name mushukistan.uz --dry-run` (the exact
   timer path) against the saved config; only then the deploy hook is installed. If either validation
   fails, the original config is restored automatically. Downtime: none.
5. **Verify**: `bash /usr/local/lib/mushukistan-tls/check-tls.sh --all` (certificate days,
   HTTP-01 routing, renewal config == Nginx mount, hook, timer, end-to-end probe file) and
   `certbot renew --dry-run` (staging; changes nothing). Deploy hooks do not run in a dry run.
6. **Confirm real automatic renewal**: the next `certbot.timer` run (within hours) renews the
   certificate for real, because it is inside the 30-day window. Check afterwards with
   `journalctl -u certbot.service --since today`, `certbot certificates` (expiry ≈ 90 days out)
   and `check-tls.sh --cert`. To avoid waiting, the owner may approve `systemctl start certbot.service`
   (the identical command the timer runs). Expected effect: a new certificate, Nginx reloaded by the
   hook, zero dropped requests.
7. **Next release**: follow phase 2 above.

## Rollback

| Situation | Action |
| --- | --- |
| The new renewal config misbehaves | `ssh -t <ssh-target> bash /usr/local/lib/mushukistan-tls/set-webroot.sh --rollback <backup file>` (owner types `TLS-ROLLBACK`). It restores the saved renewal config byte for byte. Note: that config is the broken `standalone` one, so it only restores the *previous* state. |
| Hook causes trouble | `rm /etc/letsencrypt/renewal-hooks/deploy/mushukistan-reload-nginx.sh`; reload manually after a renewal: `docker exec mushukistan-nginx nginx -t && docker exec mushukistan-nginx nginx -s reload`. |
| Emergency (certificate about to expire and renewal still failing) | One-off issuance with the webroot method, no downtime: `certbot certonly --webroot -w <A> --cert-name mushukistan.uz -d mushukistan.uz -d www.mushukistan.uz -d api.mushukistan.uz`, then the manual reload above. |

Nothing here edits the backend, worker, database, `.env` files, or any container.

## Automated checks

| Check | Command |
| --- | --- |
| Days left per hostname (WARN < 21, FAIL < 14) and HTTP-01 routing, from anywhere | `bash scripts/tls/check-tls.sh` |
| Server: authenticator, webroot == Nginx mount, hook, timer, last run | `bash /usr/local/lib/mushukistan-tls/check-tls.sh --server` |
| Server: end-to-end probe (writes and removes one token file) | `... check-tls.sh --probe` |
| Release dry run and post-switch | `activate-web-release.sh` (steps 4b and 10) |
| Weekly unattended check (example, not installed) | `infrastructure/tls/mushukistan-tls-check.{service,timer}.example` |
| Offline unit tests | `bash scripts/tls/test_tls_scripts.sh` |
| Disposable end-to-end rehearsal with a real ACME server (Pebble) | `bash scripts/tls/e2e_tls_renewal.sh` |

## Test evidence (2026-10-20, disposable environment, no production change)

Environment: a privileged Ubuntu 24.04 container as the stand-in server (same OS and the **same certbot
2.9.0** package as production) running its own Docker daemon, the repository's real Nginx config
(`infrastructure/nginx/default.conf`) with the real `docker-compose.prod.yml` ACME mount verified by
`docker compose config`, and Pebble (Let's Encrypt's official ACME test CA, validating HTTP-01 for real) with
a mock DNS pointing the three hostnames at Nginx. `bash scripts/tls/e2e_tls_renewal.sh`: **all checks passed**:

| # | What was proved |
| --- | --- |
| T1 | Root cause reproduced: with Nginx up, a standalone renewal fails with `Could not bind TCP port 80`; Docker's proxy owns the port. |
| T2 | HTTP-01 routing for `mushukistan.uz`, `www.` and `api.`: the challenge path reaches the ACME location (404 for an unknown token, no redirect) while other paths get 301 to HTTPS. |
| T3-T5 | The detector fails on the broken state and names the cause; the dry run changes nothing; a webroot that Nginx does not serve, a wrong confirmation, and a failing validation are all refused and leave the config unchanged (byte-identical) with no hook installed. |
| T6 | The switch converts standalone to webroot for all three hostnames, installs the hook, and writes a private byte-identical backup. |
| T7 | `check-tls.sh --all` (certificate days, routing, renewal config vs Nginx mount, hook, probe file) passes. |
| T8 | A real forced renewal with the **exact timer command** (`certbot -q renew --no-random-sleep-on-renew`) succeeded while a load probe made **88 HTTPS requests with 0 failures**; the new certificate (different serial) was served; the Nginx container id and `StartedAt` were unchanged (reloaded, not restarted); the hook logged the reload. |
| T9 | A release that recreates Nginx with the stable `/var/www/certbot` mount makes the detector fail and print the exact remedy; running it restores every check; a second renewal works through the stable webroot. |
| T10 | Rollback restores the original renewal config byte for byte. |

Also: `bash scripts/tls/test_tls_scripts.sh` (28 offline checks), `bash scripts/deploy/test_deploy_scripts.sh`
(58 on Linux, including the new step 4b cases) and the deploy rehearsal `bash scripts/deploy/e2e_disposable.sh` all pass
with the changed compose file.

Lessons from building it (so nobody repeats them):

- `certbot reconfigure` in 2.9.0 **rejects domains and a webroot map** ("cannot be used to modify the domains"), so it cannot switch
  a lineage to webroot. `set-webroot.sh` therefore validates with `certonly --dry-run --force-renewal`, rewrites the lineage file itself, and
  validates again with `renew --dry-run`.
- Pebble injects bad-nonce errors in 5% of requests by default (`PEBBLE_WFE_NONCEREJECT`), which made an early rehearsal flaky; the rehearsal sets
  it to 0 and also disables authorization reuse so every challenge is genuinely validated. Production Let's Encrypt does not behave like that.
- Git Bash rewrites `/path` arguments: pass `MSYS_NO_PATHCONV=1` to Docker and build certificate fixtures from a config file, not `-subj`.
- `docker exec` does not expand globs; a nested Docker daemon needs `/var/lib/docker` on a volume.

## Not covered by the rehearsal (verified only after approval, on the real server)

Real Let's Encrypt staging validation from the internet to this server; the real `certbot.timer` run; the first real renewal. These are
exactly the verification steps 5 and 6 of the production procedure.
