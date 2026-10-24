# Runs INSIDE the disposable docker:dind host started by e2e_automation.sh (bash, as root).
set -uo pipefail
fail=0; pass=0
ok()  { echo "E2E PASS  $1"; pass=$((pass+1)); }
bad() { echo "E2E FAIL  $1"; fail=$((fail+1)); }
expect_eq()   { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got '$2', want '$3')"; fi; }
expect_has()  { if grep -qF -- "$3" <<<"$2"; then ok "$1"; else bad "$1 (missing '$3')"; echo "$2" | tail -6 | sed 's/^/        /'; fi; }
expect_not()  { if grep -qF -- "$3" <<<"$2"; then bad "$1 (found '$3')"; else ok "$1"; fi; }

R=/opt/mushukistan-releases
E2E=/usr/local/lib/mushukistan-e2e
mkdir -p $R $E2E /e2e /var/www/certbot /root/mushukistan-backups
cd /src

# ---------------------------------------------------------------- miniature production stack
docker pull -q nginx:1.27-alpine >/dev/null
docker tag nginx:1.27-alpine mushukistan-backend:local
mkdir /dbimg && cat > /dbimg/Dockerfile <<'EOF'
FROM nginx:1.27-alpine
RUN printf '#!/bin/sh\nseq 1 40\n' > /usr/local/bin/pg_restore \
 && printf '#!/bin/sh\necho 123456\n' > /usr/local/bin/psql \
 && printf '#!/bin/sh\n[ -f /fail-dump ] && exit 1\nhead -c 2000 /dev/urandom\n' > /usr/local/bin/pg_dump \
 && chmod +x /usr/local/bin/pg_restore /usr/local/bin/psql /usr/local/bin/pg_dump
EOF
docker build -q -t postgis/postgis:15-3.4 /dbimg >/dev/null
mkrel() { d=$R/$1; mkdir -p $d/infrastructure/nginx $d/infrastructure/certbot/www
  cp docker-compose.yml docker-compose.prod.yml docker-compose.notifications.yml $d/
  cp infrastructure/nginx/default.conf $d/infrastructure/nginx/default.conf; }
webdirs() { d=$1; mkdir -p $d/frontend/build/web/canvaskit $d/website/dist
  printf '<html>flutter %s</html>' "$2" > $d/frontend/build/web/index.html
  printf 'var a="https://api.mushukistan.uz/api/v1/"; // %s' "$2" > $d/frontend/build/web/main.dart.js
  printf '{"useLocalCanvasKit":true}' > $d/frontend/build/web/flutter_bootstrap.js
  printf '<html>landing %s</html>' "$2" > $d/website/dist/index.html; }
echo FIREBASE > /etc/fb.json
mkdir -p /etc/letsencrypt/live/mushukistan.uz
openssl req -x509 -nodes -newkey rsa:2048 -days 2 -subj /CN=mushukistan.uz \
  -keyout /etc/letsencrypt/live/mushukistan.uz/privkey.pem -out /etc/letsencrypt/live/mushukistan.uz/fullchain.pem 2>/dev/null
overlay() { cat > $R/$1/docker-compose.notification-release.yml <<'EOF'
services:
  db:
    healthcheck: {test: ["CMD", "true"], interval: 2s, retries: 1}
  backend:
    image: mushukistan-backend:local
    command: ["nginx", "-g", "daemon off;"]
    healthcheck: {test: ["CMD", "true"], interval: 2s, retries: 1}
  notification-worker:
    image: mushukistan-backend:local
    command: ["nginx", "-g", "daemon off;"]
EOF
}
envfile() { printf 'POSTGRES_DB=x\nPOSTGRES_USER=x\nPOSTGRES_PASSWORD=e2e-super-secret-value\nFIREBASE_CREDENTIALS_HOST_PATH=/etc/fb.json\n' > $R/$1/.env; chmod 600 $R/$1/.env; }
mkrel 20260101-aaaaaaa-web; webdirs $R/20260101-aaaaaaa-web A; overlay 20260101-aaaaaaa-web; envfile 20260101-aaaaaaa-web
DC="docker compose --profile notifications -f docker-compose.yml -f docker-compose.prod.yml -f docker-compose.notifications.yml -f docker-compose.notification-release.yml"
(cd $R/20260101-aaaaaaa-web && $DC up -d --no-build db backend notification-worker nginx >/dev/null 2>&1)
sleep 3
page() { curl -sk --resolve mushukistan.uz:443:127.0.0.1 https://mushukistan.uz/index.html; }
others() { docker ps -q | xargs docker inspect --format '{{.Name}} {{.Id}}' | grep -v nginx | sort; }
expect_eq "fixture: release A is served" "$(page)" "<html>flutter A</html>"
OTHERS="$(others)"

# local stand-ins for public HTTPS checks (root-owned, referenced from broker.conf)
cat > $E2E/verify-local.sh <<'EOF'
#!/usr/bin/env bash
dir="$2"
[ -f /etc/mushukistan-e2e/verify-sleep ] && sleep "$(cat /etc/mushukistan-e2e/verify-sleep)"
if [ -f /etc/mushukistan-e2e/verify-fail ] && [[ "$dir" == *"$(cat /etc/mushukistan-e2e/verify-fail)"* ]]; then echo "FAIL  forced"; exit 1; fi
got="$(curl -sk --resolve mushukistan.uz:443:127.0.0.1 https://mushukistan.uz/index.html)"
[ "$got" = "$(cat "$dir/index.html")" ] && echo "ALL CHECKS PASSED ($got)" || { echo "FAIL served '$got'"; exit 1; }
EOF
printf '#!/usr/bin/env bash\necho "ALL TLS CHECKS PASSED"\n' > $E2E/check-tls.sh
chmod 755 $E2E/*.sh; mkdir -p /etc/mushukistan-e2e

# ---------------------------------------------------------------- sshd + install
ssh-keygen -A >/dev/null
if [ "${E2E_DISTRO:-alpine}" = alpine ]; then
cat > /etc/ssh/sshd_config <<'EOF'
Include /etc/ssh/sshd_config.d/*.conf
PermitRootLogin no
PasswordAuthentication no
Subsystem sftp internal-sftp
EOF
fi   # ubuntu: keep the distribution's sshd_config (Include first, UsePAM/AcceptEnv/Subsystem after it)
echo "E2E INFO  distro=${E2E_DISTRO:-alpine} $(ssh -V 2>&1) $(sudo -V | head -1) $(python3 --version) compose $(docker compose version --short)"
mkdir -p /etc/ssh/sshd_config.d /run/sshd
ssh-keygen -q -t ed25519 -N "" -C owner -f /e2e/owner      # test-only: real owners use FIDO2/passphrase
ssh-keygen -q -t ed25519 -N "" -C deploy -f /e2e/deploy
ssh-keygen -q -t ed25519 -N "" -C intruder -f /e2e/intruder
sed -e "s#^VERIFY_SCRIPT=.*#VERIFY_SCRIPT=$E2E/verify-local.sh#" -e "s#^TLS_CHECK_SCRIPT=.*#TLS_CHECK_SCRIPT=$E2E/check-tls.sh#" \
  -e "s#^HEALTH_URL=.*#HEALTH_URL=http://127.0.0.1/health#" -e "s#^DOCKER=.*#DOCKER=$(command -v docker)#" \
  scripts/deploy/automation/broker.conf.example > /e2e/broker.conf
echo "SOURCE_ARCHIVE_URL=file:///e2e/srcarch/{commit}.tar.gz" >> /e2e/broker.conf
INSTALL=scripts/deploy/automation/install-server.sh
out="$(RELOAD_SSH=true bash $INSTALL --owner-key /e2e/owner.pub --deploy-key /e2e/deploy.pub --config /e2e/broker.conf)"
expect_has "installer dry run changes nothing" "$out" "DRY RUN"
expect_eq "no account after dry run" "$(id mushukistan-deploy 2>/dev/null | wc -l)" "0"
expect_has "installer refuses identical owner/deploy keys" \
  "$(RELOAD_SSH=true bash $INSTALL --owner-key /e2e/deploy.pub --deploy-key /e2e/deploy.pub --execute 2>&1)" "must differ"
out="$(RELOAD_SSH=true bash $INSTALL --owner-key /e2e/owner.pub --deploy-key /e2e/deploy.pub --config /e2e/broker.conf --execute 2>&1)"
expect_has "installer --execute" "$out" "installed."
/usr/sbin/sshd
sleep 1

X() { ssh -i /e2e/deploy -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o LogLevel=ERROR \
      mushukistan-deploy@127.0.0.1 "$@" 2>&1; }
AS_DEPLOY() { su -s /bin/sh mushukistan-deploy -c "$1" 2>&1; }

# ---------------------------------------------------------------- restricted identity
expect_has "status works through the forced command" "$(X status)" "active Nginx release : 20260101-aaaaaaa-web"
expect_has "no shell: bash refused" "$(X bash)" "unknown command"
expect_has "no shell: chained command refused" "$(X 'status; id')" "invalid characters"
expect_has "no shell: substitution refused" "$(X 'status $(id)')" "invalid characters"
expect_has "path traversal argument refused" "$(X upload ../../etc/passwd)" "invalid"
expect_has "PTY refused" "$(ssh -tt -i /e2e/deploy -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR mushukistan-deploy@127.0.0.1 status 2>&1)" "PTY allocation request failed"
SSHO="-i /e2e/deploy -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes"
expect_has "sftp subsystem refused" "$(echo 'ls /' | sftp $SSHO -b - mushukistan-deploy@127.0.0.1 2>&1; echo rc=$?)" "rc=255"
scp $SSHO /etc/hostname mushukistan-deploy@127.0.0.1:/tmp/scp-escape >/dev/null 2>&1
expect_eq "scp upload refused" "$(ls /tmp/scp-escape 2>/dev/null | wc -l)" "0"
ssh $SSHO -N -L 127.0.0.1:18022:127.0.0.1:22 mushukistan-deploy@127.0.0.1 2>/e2e/fwd.err & FWD=$!
sleep 2; timeout 5 bash -c 'exec 3<>/dev/tcp/127.0.0.1/18022; head -c 20 <&3' >/e2e/fwd.out 2>&1; kill $FWD 2>/dev/null; wait $FWD 2>/dev/null
expect_has "TCP port forwarding refused by the server" "$(cat /e2e/fwd.err)" "prohibited"
expect_not "no SSH banner through the forward" "$(cat /e2e/fwd.out)" "SSH-2.0"
expect_has "client environment cannot reach the gate" "$(ssh $SSHO -o LogLevel=ERROR -o SetEnv=SSH_ORIGINAL_COMMAND=bash mushukistan-deploy@127.0.0.1 2>&1)" "no command given"
expect_has "intruder key cannot log in" "$(ssh -i /e2e/intruder -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes mushukistan-deploy@127.0.0.1 status 2>&1)" "Permission denied"
eff="$(sshd -T -C user=mushukistan-deploy,host=x,addr=127.0.0.1)"
expect_has "sshd: forced command" "$eff" "forcecommand /usr/local/lib/mushukistan-deploy/deploy-gate"
expect_has "sshd: no tcp forwarding" "$eff" "allowtcpforwarding no"
expect_has "sshd: no tty" "$eff" "permittty no"
expect_has "sshd: global settings unaffected for other users" "$(sshd -T -C user=root,host=x,addr=127.0.0.1)" "permittty yes"
expect_has "deploy user: sudo only for the broker" "$(AS_DEPLOY 'sudo -n /bin/sh -c id')" "a password is required"
expect_has "deploy user: sudo -l lists only the broker" "$(AS_DEPLOY 'sudo -n -l')" "/usr/local/lib/mushukistan-deploy/broker"
expect_not "deploy user: not in docker group" "$(id -nG mushukistan-deploy)" "docker"
expect_has "deploy user: no docker socket" "$(AS_DEPLOY 'docker ps')" "permission denied"
expect_has "deploy user: cannot read broker state" "$(AS_DEPLOY 'ls /var/lib/mushukistan-deploy')" "Permission denied"
expect_has "deploy user: cannot modify the broker" "$(AS_DEPLOY 'echo x >> /usr/local/lib/mushukistan-deploy/broker')" "Permission denied"
expect_has "deploy user: cannot modify allowed_signers" "$(AS_DEPLOY 'echo x >> /etc/mushukistan-deploy/allowed_signers')" "Permission denied"
expect_has "deploy user: cannot read production .env" "$(AS_DEPLOY "cat $R/20260101-aaaaaaa-web/.env")" "Permission denied"
chmod g+w /usr/local/lib/mushukistan-deploy/activate-web-release.sh
expect_has "broker refuses a group-writable trusted script" "$(X status)" "not group/world-writable"
chmod g-w /usr/local/lib/mushukistan-deploy/activate-web-release.sh

# ---------------------------------------------------------------- release artifacts + approvals
COMMIT=cccccccccccccccccccccccccccccccccccccccc
newrel() { # name label [extra-mutation]
  local n=$1 d=/build/$1; rm -rf /build; mkdir -p /build; R_SAVE=$R; R=/build; mkrel $n; R=$R_SAVE
  webdirs $d "$2"; echo "$COMMIT" > $d/RELEASE_COMMIT.txt
  tar -C /build -czf /e2e/$n.tar.gz $n; sha256sum /e2e/$n.tar.gz | cut -d' ' -f1; }
approve() { # name sha256 ops [ttl] [key] [env] [issued_offset_min] -> prints approval id
  python3 - "$@" <<'PY'
import os, subprocess, sys
from datetime import timedelta
sys.path.insert(0, "/src/scripts/deploy/automation")
import approval_schema as s
name, sha, ops = sys.argv[1], sys.argv[2], sys.argv[3].split(",")
ttl = int(sys.argv[4]) if len(sys.argv) > 4 else 30
key = sys.argv[5] if len(sys.argv) > 5 else "/e2e/owner"
env = sys.argv[6] if len(sys.argv) > 6 else "production"
off = int(sys.argv[7]) if len(sys.argv) > 7 else 0
aid = os.urandom(16).hex()
doc = {"version": 1, "type": "web-release", "approval_id": aid, "environment": env, "release": name,
       "commit": "c" * 40, "artifact_sha256": sha, "operations": ops,
       "issued_at": s.format_time(s.utc_now() + timedelta(minutes=off)),
       "expires_at": s.format_time(s.utc_now() + timedelta(minutes=off + ttl))}
p = f"/e2e/{aid}.json"; open(p, "wb").write(s.canonical_bytes(doc))
subprocess.run(["ssh-keygen", "-q", "-Y", "sign", "-f", key, "-n", s.NAMESPACE, p], check=True, capture_output=True)
print(aid)
PY
}
signed() { # kind json-fields... -> id ; for web-rollback and revocation documents
  python3 - "$@" <<'PY'
import json, os, subprocess, sys
from datetime import timedelta
sys.path.insert(0, "/src/scripts/deploy/automation")
import approval_schema as s
kind, value = sys.argv[1], sys.argv[2]
aid = os.urandom(16).hex()
doc = {"version": 1, "type": kind, "approval_id": aid, "environment": "production",
       "issued_at": s.format_time(s.utc_now()), "expires_at": s.format_time(s.utc_now() + timedelta(minutes=20))}
if kind == "web-rollback": doc.update(release=value, operations=["rollback"])
else: doc["revokes"] = value
p = f"/e2e/{aid}.json"; open(p, "wb").write(s.canonical_bytes(doc))
subprocess.run(["ssh-keygen", "-q", "-Y", "sign", "-f", "/e2e/owner", "-n", s.NAMESPACE, p], check=True, capture_output=True)
print(aid)
PY
}
envelope() { python3 -c 'import base64,json,sys; d=open(sys.argv[1],"rb").read(); print(json.dumps({"document":base64.b64encode(d).decode(),"signature":open(sys.argv[1]+".sig").read()}))' "/e2e/$1.json"; }
submit() { envelope "$1" | X submit-approval; }

REL1=20260201-ccccccc-feed
SHA1="$(newrel $REL1 B)"
# stand-in for codeload.github.com: the commit's tracked files = the release minus build outputs
mkdir -p /e2e/srcarch /srcwork && cp -r /build/$REL1 /srcwork/Mushukent-$COMMIT
rm -rf /srcwork/Mushukent-$COMMIT/frontend/build /srcwork/Mushukent-$COMMIT/website/dist /srcwork/Mushukent-$COMMIT/RELEASE_COMMIT.txt
tar -C /srcwork -czf /e2e/srcarch/$COMMIT.tar.gz Mushukent-$COMMIT
expect_has "upload without approval refused" "$(X upload $REL1 < /e2e/$REL1.tar.gz)" "no active owner approval"
SELF="$(approve $REL1 $SHA1 stage,backup,activate,auto-rollback 30 /e2e/deploy)"
expect_has "self-approval with the deploy key refused" "$(submit $SELF)" "signature is not valid"
WENV="$(approve $REL1 $SHA1 stage 30 /e2e/owner staging)"
expect_has "wrong environment refused" "$(submit $WENV)" "environment"
EXP="$(approve $REL1 $SHA1 stage 10 /e2e/owner production -30)"
expect_has "expired approval refused" "$(submit $EXP)" "expired"
LONG="$(approve $REL1 $SHA1 stage 600)"
expect_has "lifetime above server maximum refused" "$(submit $LONG)" "maximum"
A1="$(approve $REL1 $SHA1 stage,backup,activate,auto-rollback)"
expect_has "valid approval accepted" "$(submit $A1)" "accepted"
expect_has "wrong artifact bytes refused" "$(printf 'not the archive' | X upload $REL1)" "does not match the approved"
expect_eq "no partial upload left" "$(ls /var/lib/mushukistan-deploy/artifacts | wc -l)" "0"
expect_has "approved artifact uploaded" "$(X upload $REL1 < /e2e/$REL1.tar.gz)" "SHA-256 matches"
expect_has "deploy with an unknown approval id refused" "$(X deploy ffffffffffffffffffffffffffffffff)" "no such approval"
out="$(X deploy $A1)"
expect_has "deploy: DEPLOYED AND VERIFIED" "$out" "RESULT: DEPLOYED AND VERIFIED"
expect_has "deploy: non-interactive path used" "$out" "authorized by server-verified approval $A1"
expect_has "deploy: source verified against the commit" "$out" "source verified"
expect_eq "new release served" "$(page)" "<html>flutter B</html>"
expect_eq "backend/worker/db containers untouched" "$(others)" "$OTHERS"
expect_eq "backup written" "$(ls /root/mushukistan-backups/*auto-ccccccc.dump | wc -l)" "1"
expect_has "PREVIOUS_STATE records the approval" "$(cat $R/$REL1/PREVIOUS_STATE.txt)" "approval_id=$A1"
expect_eq "staged .env is root-only" "$(stat -c %a $R/$REL1/.env)" "600"
expect_has "replayed deploy refused" "$(X deploy $A1)" "approval is consumed"
expect_has "replayed approval submission refused" "$(submit $A1)" "replay refused"
expect_eq "no approval tokens left" "$(ls /run/mushukistan-deploy | wc -l)" "0"

# malicious archive: traversal + symlink, approved by the owner (hash matches) but refused at staging
REL2=20260202-ccccccc-evil
python3 - $REL2 <<'PY'
import io, sys, tarfile
n = sys.argv[1]
with tarfile.open(f"/e2e/{n}.tar.gz", "w:gz") as tf:
    for name, kind in ((f"{n}/../../../etc/cron.d/evil", tarfile.REGTYPE), (f"{n}/link", tarfile.SYMTYPE)):
        m = tarfile.TarInfo(name); m.type = kind; m.linkname = "/etc/shadow" if kind == tarfile.SYMTYPE else ""
        data = b"* * * * * root id\n"; m.size = len(data) if kind == tarfile.REGTYPE else 0
        tf.addfile(m, io.BytesIO(data) if kind == tarfile.REGTYPE else None)
PY
SHA2="$(sha256sum /e2e/$REL2.tar.gz | cut -d' ' -f1)"
A2="$(approve $REL2 $SHA2 stage)"; submit $A2 >/dev/null; X upload $REL2 < /e2e/$REL2.tar.gz >/dev/null
expect_has "malicious archive refused" "$(X deploy $A2)" "outside $REL2/"
expect_eq "nothing written outside the release root" "$(ls /etc/cron.d/evil 2>/dev/null | wc -l)" "0"
expect_eq "no release dir for the malicious archive" "$(ls -d $R/$REL2 2>/dev/null | wc -l)" "0"

# failed backup: nothing activated
REL3=20260203-ccccccc-nobackup
SHA3="$(newrel $REL3 C)"; A3="$(approve $REL3 $SHA3 stage,backup,activate,auto-rollback)"
submit $A3 >/dev/null; X upload $REL3 < /e2e/$REL3.tar.gz >/dev/null
docker exec mushukistan-db touch /fail-dump
expect_has "failed backup refused" "$(X deploy $A3)" "backup failed"
docker exec mushukistan-db rm /fail-dump
expect_eq "still release B after failed backup" "$(page)" "<html>flutter B</html>"

# tampered build: owner-approved hash, but the Nginx config differs from the commit
REL4=20260204-ccccccc-badconf
newrel $REL4 D >/dev/null; echo 'this is not nginx config;' >> /build/$REL4/infrastructure/nginx/default.conf
tar -C /build -czf /e2e/$REL4.tar.gz $REL4; SHA4="$(sha256sum /e2e/$REL4.tar.gz | cut -d' ' -f1)"
A4="$(approve $REL4 $SHA4 stage,backup,activate,auto-rollback)"; submit $A4 >/dev/null; X upload $REL4 < /e2e/$REL4.tar.gz >/dev/null
out="$(X deploy $A4)"
expect_has "tampered Nginx config refused by source verification" "$out" "does not match the source"
expect_has "the differing file is named" "$out" "infrastructure/nginx/default.conf: differs"
expect_eq "tampered release directory removed" "$(ls -d $R/$REL4 2>/dev/null | wc -l)" "0"
expect_eq "still release B after the tampered build" "$(page)" "<html>flutter B</html>"

# failed preflight (bundle check): refused before any backup or change
REL4b=20260204-ccccccc-nocanvaskit
newrel $REL4b D >/dev/null; rm -rf /build/$REL4b/frontend/build/web/canvaskit
tar -C /build -czf /e2e/$REL4b.tar.gz $REL4b; SHA4b="$(sha256sum /e2e/$REL4b.tar.gz | cut -d' ' -f1)"
A4b="$(approve $REL4b $SHA4b stage,backup,activate,auto-rollback)"; submit $A4b >/dev/null; X upload $REL4b < /e2e/$REL4b.tar.gz >/dev/null
nb="$(ls /root/mushukistan-backups | wc -l)"
expect_has "preflight failure refused" "$(X deploy $A4b)" "preflight failed"
expect_eq "no backup taken after a failed preflight" "$(ls /root/mushukistan-backups | wc -l)" "$nb"
expect_eq "still release B after failed preflight" "$(page)" "<html>flutter B</html>"

# smoke-test failure with auto-rollback
REL5=20260205-ccccccc-smokefail
SHA5="$(newrel $REL5 E)"; A5="$(approve $REL5 $SHA5 stage,backup,activate,auto-rollback)"
submit $A5 >/dev/null; X upload $REL5 < /e2e/$REL5.tar.gz >/dev/null
echo $REL5 > /etc/mushukistan-e2e/verify-fail
expect_has "smoke failure is rolled back automatically" "$(X deploy $A5)" "RESULT: ROLLED BACK"
expect_eq "release B served again after auto-rollback" "$(page)" "<html>flutter B</html>"
expect_eq "containers untouched after auto-rollback" "$(others)" "$OTHERS"

# smoke failure WITHOUT auto-rollback -> explicit approved rollback; unauthorized rollback denied
REL6=20260206-ccccccc-manualrb
SHA6="$(newrel $REL6 F)"; A6="$(approve $REL6 $SHA6 stage,backup,activate)"
submit $A6 >/dev/null; X upload $REL6 < /e2e/$REL6.tar.gz >/dev/null
echo $REL6 > /etc/mushukistan-e2e/verify-fail
expect_has "no auto-rollback without approval scope" "$(X deploy $A6)" "does not include auto-rollback"
expect_eq "failed release stays until an approved rollback" "$(page)" "<html>flutter F</html>"
rm /etc/mushukistan-e2e/verify-fail
expect_has "rollback with a release approval denied" "$(X rollback $A6)" "approval is failed"
RBW="$(signed web-rollback $REL1)"; submit $RBW >/dev/null
expect_has "rollback approval for a non-active release denied" "$(X rollback $RBW)" "currently runs $REL6"
RB="$(signed web-rollback $REL6)"; submit $RB >/dev/null
expect_has "approved rollback" "$(X rollback $RB)" "RESULT: ROLLED BACK"
expect_eq "release B served after approved rollback" "$(page)" "<html>flutter B</html>"
expect_has "rollback approval cannot be reused" "$(X rollback $RB)" "approval is consumed"

# revocation and executor cancel
REL7=20260207-ccccccc-revoked
SHA7="$(newrel $REL7 G)"; A7="$(approve $REL7 $SHA7 stage,backup,activate,auto-rollback)"; submit $A7 >/dev/null
REV="$(signed revocation $A7)"
expect_has "owner revocation accepted" "$(submit $REV)" "revoked"
expect_has "revoked approval refused" "$(X upload $REL7 < /e2e/$REL7.tar.gz)" "no active owner approval"
A7b="$(approve $REL7 $SHA7 stage)"; submit $A7b >/dev/null
expect_has "executor may cancel (only reduces rights)" "$(X cancel $A7b)" "cancelled"

# interruption: broker killed after the switch, during verification
REL8=20260208-ccccccc-interrupt
SHA8="$(newrel $REL8 H)"; A8="$(approve $REL8 $SHA8 stage,backup,activate,auto-rollback)"
submit $A8 >/dev/null; X upload $REL8 < /e2e/$REL8.tar.gz >/dev/null
echo 30 > /etc/mushukistan-e2e/verify-sleep
X deploy $A8 > /e2e/interrupt.log &
for _ in $(seq 1 60); do [ "$(page)" = "<html>flutter H</html>" ] && break; sleep 1; done
sleep 2; pkill -9 -f "mushukistan-deploy/broker deploy"; sleep 1
rm /etc/mushukistan-e2e/verify-sleep
wait 2>/dev/null
expect_has "interrupted approval is reported and refused" "$(X deploy $A8)" "approval is interrupted"
expect_eq "no tokens left after interruption" "$(ls /run/mushukistan-deploy | wc -l)" "0"
expect_has "interruption is in the audit history" "$(X history 50)" "interrupted"
RB8="$(signed web-rollback $REL8)"; submit $RB8 >/dev/null
expect_has "approved rollback recovers from the interruption" "$(X rollback $RB8)" "RESULT: ROLLED BACK"
expect_eq "release B after recovery" "$(page)" "<html>flutter B</html>"

# client disconnect: the SSH client dies mid-deploy, the broker finishes and records the result
REL9=20260209-ccccccc-disconnect
SHA9="$(newrel $REL9 I)"; A9="$(approve $REL9 $SHA9 stage,backup,activate,auto-rollback)"
submit $A9 >/dev/null; X upload $REL9 < /e2e/$REL9.tar.gz >/dev/null
echo 8 > /etc/mushukistan-e2e/verify-sleep
timeout 6 ssh -i /e2e/deploy -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o LogLevel=ERROR \
  mushukistan-deploy@127.0.0.1 deploy $A9 >/dev/null 2>&1 || true
for _ in $(seq 1 60); do grep -q "\"approval_id\": \"$A9\".*\"verb\": \"activate\".*\"result\": \"ok\"\|\"approval_id\": \"$A9\", \"detail\": \"verified" /var/lib/mushukistan-deploy/audit.log 2>/dev/null && break; sleep 1; done
rm -f /etc/mushukistan-e2e/verify-sleep
expect_has "deploy completed after the client disconnected" "$(X approvals | grep $A9)" "consumed"
expect_eq "release I served after disconnect" "$(page)" "<html>flutter I</html>"

# operator CLI (release_web.py) end to end against the disposable server
REL10=20260210-ccccccc-cli
SHA10="$(newrel $REL10 J)"
A10="$(approve $REL10 $SHA10 stage,backup,activate,auto-rollback)"
mkdir -p /src/release/automation/approvals
cp /e2e/$A10.json /src/release/automation/approvals/$REL10.$A10.json
cp /e2e/$A10.json.sig /src/release/automation/approvals/$REL10.$A10.json.sig
python3 - "$REL10" "$SHA10" <<'PY'
import json, sys
name, sha = sys.argv[1], sys.argv[2]
json.dump({"release": name, "commit": "c" * 40, "artifact": f"/e2e/{name}.tar.gz", "artifact_sha256": sha,
           "artifact_bytes": 0, "main_dart_js_sha256": "-", "ci": [], "worktree": "/tmp", "scope": "web only",
           "default_operations": [], "prepared_at": "-"}, open(f"/src/release/automation/{name}.plan.json", "w"))
PY
mkdir -p /root/.ssh; ssh-keyscan -t ed25519 127.0.0.1 2>/dev/null > /root/.ssh/known_hosts
CLI() { MUSHUKISTAN_DEPLOY_TARGET=mushukistan-deploy@127.0.0.1 MUSHUKISTAN_DEPLOY_KEY=/e2e/deploy \
        python3 /src/scripts/deploy/release_web.py "$@" 2>&1; }
out="$(CLI deploy $REL10 --skip-local-verify)"
expect_has "CLI deploy: submit + upload + deploy in one command" "$out" "RESULT: DEPLOYED AND VERIFIED"
expect_eq "CLI deploy: release J served" "$(page)" "<html>flutter J</html>"
expect_has "CLI deploy: report written" "$(cat /src/release/automation/$REL10.report.md)" "Result: DEPLOYED AND VERIFIED"
expect_has "CLI status" "$(CLI status)" "active Nginx release : $REL10"
expect_has "CLI history" "$(CLI history 5)" "activate"
expect_has "CLI owner commands refuse a non-terminal" "$(CLI approve $REL10 </dev/null)" "interactive terminal"
expect_has "CLI refuses a tampered artifact" "$(echo x >> /e2e/$REL10.tar.gz; CLI deploy $REL10 --skip-local-verify)" "artifact changed after prepare"

# history, secrets, cleanup
hist="$(X history 200)"
expect_has "history shows activations" "$hist" "activate"
expect_not "audit history holds no secret values" "$hist$(cat /var/lib/mushukistan-deploy/audit.log)" "e2e-super-secret-value"
expect_eq "no staging leftovers" "$(ls -d $R/.staging-* 2>/dev/null | wc -l)" "0"
expect_eq "no partial uploads" "$(ls /var/lib/mushukistan-deploy/artifacts/*.partial 2>/dev/null | wc -l)" "0"
expect_eq "no release directory was deleted (A + 8 staged)" "$(ls -d $R/2026* | wc -l)" "9"
expect_eq "release A still present for rollback" "$(ls $R/20260101-aaaaaaa-web/frontend/build/web/index.html)" "$R/20260101-aaaaaaa-web/frontend/build/web/index.html"

# uninstall removes access; the manual workflow is unaffected
NGINX_BEFORE="$(docker inspect -f '{{.Id}}' mushukistan-nginx)"; ALL_BEFORE="$(others)"; RELS_BEFORE="$(ls -d $R/2026* | wc -l)"
RELOAD_SSH="pkill -HUP -x sshd" bash $INSTALL --uninstall --execute >/dev/null 2>&1; sleep 1
expect_has "after uninstall the deploy key cannot log in" "$(X status)" "Permission denied"
expect_eq "uninstall: Nginx container untouched" "$(docker inspect -f '{{.Id}}' mushukistan-nginx)" "$NGINX_BEFORE"
expect_eq "uninstall: backend/worker/db untouched" "$(others)" "$ALL_BEFORE"
expect_eq "uninstall: release directories kept" "$(ls -d $R/2026* | wc -l)" "$RELS_BEFORE"
expect_eq "uninstall: database volume kept" "$(docker volume ls -q | grep -c postgres_data)" "1"
expect_has "uninstall: ACME webroot still mounted into Nginx" "$(docker inspect -f '{{range .Mounts}}{{.Source}} {{end}}' mushukistan-nginx)" "/var/www/certbot"
expect_has "uninstall: audit log kept" "$(ls /var/lib/mushukistan-deploy)" "audit.log"
# manual workflow (typed confirmations through a real pty) still works without the automation
export VERIFY_SCRIPT=$E2E/verify-local.sh
out="$(printf 'BACKUP manual-after-uninstall\n' | script -qec "bash /src/scripts/deploy/backup-db.sh --label manual-after-uninstall --execute" /dev/null)"
expect_has "manual typed backup still works" "$out" "pg_restore --list entries: 40"
DUMP="$(ls -t /root/mushukistan-backups/*manual-after-uninstall.dump | head -1)"
out="$(printf 'ACTIVATE %s\n' "$REL9" | script -qec "bash /src/scripts/deploy/activate-web-release.sh $REL9 --execute --backup-file $DUMP" /dev/null)"
expect_has "manual typed activation still works" "$out" "public verification passed"
expect_eq "manual activation switched Nginx" "$(page)" "<html>flutter I</html>"
expect_has "manual activation records approval_id=manual" "$(cat $R/$REL9/PREVIOUS_STATE.txt)" "approval_id=manual"

echo; echo "E2E: $pass passed, $fail failed"
[ "$fail" -eq 0 ] && echo "E2E ALL PASSED" || exit 1
