# Uptime monitoring (public URLs, ops Telegram alerts, dead-man's switch)

**Why:** on 2026-11-23 the root domain returned Cloudflare 522/525 for about nine minutes
(09:03–09:12 UTC) and nobody was told. The host health timer (`docs/OBSERVABILITY_PLAN.md`) watches
containers and Nginx 5xx; it cannot see a failure between Cloudflare and the origin.

## What runs

| Piece | Where on the server | Source in this repo |
| --- | --- | --- |
| Check script (Python 3 standard library) | `/usr/local/lib/mushukistan-ops/uptime_check.py` | `infrastructure/ops/uptime_check.py` |
| One-minute timer (at :30, so it does not overlap the host health run at :00) | `/etc/systemd/system/mushukistan-uptime.{service,timer}` | `infrastructure/ops/mushukistan-uptime.*.example` |
| Telegram secrets (shared with the host health timer) | `/etc/mushukistan-ops/host-health.env` | `infrastructure/ops/host-health.env.example` |
| Optional settings and the heartbeat URL | `/etc/mushukistan-ops/uptime.env` (root, 600) | `infrastructure/ops/uptime.env.example` |
| Check log, one line per URL per minute | `/var/log/mushukistan-ops/uptime.log` | rotated by `/etc/logrotate.d/mushukistan-uptime` (daily, 60 days) |
| State (consecutive failures, alert sent) | `/var/lib/mushukistan-ops/uptime.json` | |

Every minute it requests `https://mushukistan.uz/`, `https://www.mushukistan.uz/` (through Cloudflare)
and `https://api.mushukistan.uz/health` (DNS-only, straight to the origin), in parallel, 15 s timeout
each, redirects not followed, and expects 200.

- **DOWN**: after 2 consecutive failed runs of one URL, one message to the ops chat (the same bot, chat and `🚨 OPS ·` prefix as the backend and host alerts) with the
  host, the HTTP code or error (`522`, `525`, `timeout`, `tls`, `dns`, `refused`, `reset`) and UTC
  times. Nothing more while it stays down.
- **RECOVERED**: one `✅ OPS ·` message at the first success, with the downtime counted from the first
  failed check. A single failed run sends nothing.
- A message that cannot be delivered is retried on the next run.
- Log line format: `2026-11-23T09:04:15Z mushukistan.uz 522 19580ms FAIL`. Analysis examples:
  `grep FAIL /var/log/mushukistan-ops/uptime.log`, or
  `zcat -f /var/log/mushukistan-ops/uptime.log* | awk '{print $2,$3}' | sort | uniq -c`.

Limits: the check runs on the production host itself, so it cannot report the host, its network or
the timer being down. The dead-man's switch below covers that. A Cloudflare problem that affects
only some Cloudflare data centres can be missed: the host reaches Cloudflare through the data centre nearest to it, not the one users in Uzbekistan use.

## Dead-man's switch (healthchecks.io, free plan)

After every run the script sends one HTTPS request to `HEALTHCHECK_PING_URL`. If the pings stop,
healthchecks.io alerts.

The owner sets it up (the agent does not sign up for anything):

1. Create a free account at <https://healthchecks.io> and a check named `mushukistan-prod-uptime`.
   Schedule: **Simple**, period **1 minute**, grace **5 minutes**.
2. Integrations: add **Telegram** (healthchecks.io has its own bot, so this still works when the server
   is down) and/or email.
3. Copy the check's ping URL (`https://hc-ping.com/<uuid>`). It is a secret: whoever has it can
   silence the alarm. Put it on the server only:
   `install -m 600 /dev/null /etc/mushukistan-ops/uptime.env` and then add the line
   `HEALTHCHECK_PING_URL=https://hc-ping.com/<uuid>` with an editor (not echoed in a logged shell).
4. Nothing to restart: the next timer run reads it. healthchecks.io shows the check as "up" within
   a minute.

## Disable or remove (touches no container)

```sh
systemctl disable --now mushukistan-uptime.timer          # stop checking (keeps files and log)
# full removal:
rm -f /etc/systemd/system/mushukistan-uptime.service /etc/systemd/system/mushukistan-uptime.timer \
      /etc/logrotate.d/mushukistan-uptime /usr/local/lib/mushukistan-ops/uptime_check.py \
      /var/lib/mushukistan-ops/uptime.json /etc/mushukistan-ops/uptime.env
systemctl daemon-reload
```

Pause the healthchecks.io check first, or it alerts when the pings stop.

Tests: `backend/tests/test_uptime_check_script.py`.
