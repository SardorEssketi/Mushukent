#!/usr/bin/env bash
# Install (or remove) the approval-based deployment interface ON the server, as root.
# Run by the OWNER only, from an unpacked copy of a reviewed main commit:
#
#   install-server.sh --owner-key owner_approval.pub --deploy-key deploy.pub            # dry run
#   install-server.sh --owner-key owner_approval.pub --deploy-key deploy.pub --execute  # install
#   install-server.sh --uninstall --execute     # remove access; keeps state and the audit log
#
# What it creates (docs/DEPLOYMENT_AUTOMATION.md, "Installation"):
#   user mushukistan-deploy        system account, no password, not in the docker group
#   /usr/local/lib/mushukistan-deploy/   root-owned: deploy-gate, broker, approval_schema.py,
#                                        activate-web-release.sh, backup-db.sh, verify-public.sh,
#                                        approval-token.sh
#   /etc/mushukistan-deploy/       broker.conf, allowed_signers (owner key), authorized_keys
#   /etc/sudoers.d/mushukistan-deploy    exactly one command: the broker
#   /etc/ssh/sshd_config.d/60-mushukistan-deploy.conf   ForceCommand deploy-gate, no TTY/forwarding
# It validates sudoers with visudo and sshd with `sshd -t` before reloading ssh.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
DEPLOY_DIR="$HERE/.."
USER_NAME="mushukistan-deploy"
LIB=/usr/local/lib/mushukistan-deploy
ETC=/etc/mushukistan-deploy
SUDOERS=/etc/sudoers.d/mushukistan-deploy
SSHD_SNIPPET=/etc/ssh/sshd_config.d/60-mushukistan-deploy.conf
owner_key=""; deploy_key=""; execute=0; uninstall=0; config="$HERE/broker.conf.example"
RELOAD_SSH="${RELOAD_SSH:-systemctl reload ssh}"

die() { echo "ERROR: $*" >&2; exit 1; }
while [ $# -gt 0 ]; do
  case "$1" in
    --owner-key) owner_key="${2:?}"; shift 2 ;;
    --deploy-key) deploy_key="${2:?}"; shift 2 ;;
    --config) config="${2:?}"; shift 2 ;;
    --execute) execute=1; shift ;;
    --uninstall) uninstall=1; shift ;;
    -h|--help) sed -n '2,19p' "$0"; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done
[ "$(id -u)" = 0 ] || die "run as root"

if [ "$uninstall" -eq 1 ]; then
  echo "plan: remove $SSHD_SNIPPET, $SUDOERS, $ETC/authorized_keys and lock $USER_NAME (state and audit log are kept)"
  [ "$execute" -eq 1 ] || { echo "DRY RUN: nothing changed"; exit 0; }
  rm -f "$SSHD_SNIPPET" "$SUDOERS" "$ETC/authorized_keys"
  if id "$USER_NAME" >/dev/null 2>&1; then usermod -L -s /usr/sbin/nologin "$USER_NAME"; fi
  sshd -t && $RELOAD_SSH
  echo "removed: the deployment identity can no longer log in; manual workflow unaffected"
  exit 0
fi

[ -f "$owner_key" ] && [ -f "$deploy_key" ] || die "--owner-key and --deploy-key public key files are required"
okey="$(head -1 "$owner_key")"; dkey="$(head -1 "$deploy_key")"
[[ "$okey" =~ ^(sk-ssh-ed25519@openssh.com|ssh-ed25519|sk-ecdsa-sha2-nistp256@openssh.com)\ [A-Za-z0-9+/=]+ ]] \
  || die "owner key must be an ed25519 or FIDO2 public key"
[[ "$dkey" =~ ^ssh-ed25519\ [A-Za-z0-9+/=]+ ]] || die "deploy key must be an ssh-ed25519 public key"
[ "$(echo "$okey" | awk '{print $2}')" != "$(echo "$dkey" | awk '{print $2}')" ] || die "owner and deploy keys must differ"
for f in deploy_gate.py broker.py approval_schema.py; do [ -f "$HERE/$f" ] || die "missing $HERE/$f"; done
for f in activate-web-release.sh backup-db.sh verify-public.sh approval-token.sh; do [ -f "$DEPLOY_DIR/$f" ] || die "missing $f"; done
python3 -c 'import sys; sys.exit(sys.version_info < (3, 12))' || die "python3 >= 3.12 required"

echo "plan:"
echo "  user      : $USER_NAME (system, locked password, shell /bin/sh for the forced command, NOT in group docker)"
echo "  programs  : $LIB (root:root, 0755/0644)"
echo "  config    : $ETC/broker.conf, $ETC/allowed_signers (owner: ${okey%% *}), $ETC/authorized_keys"
echo "  sudoers   : $SUDOERS -> $USER_NAME may run only $LIB/broker"
echo "  sshd      : $SSHD_SNIPPET -> ForceCommand $LIB/deploy-gate, no TTY, no forwarding"
[ "$execute" -eq 1 ] || { echo "DRY RUN: nothing changed (add --execute)"; exit 0; }

if ! id "$USER_NAME" >/dev/null 2>&1; then
  if command -v useradd >/dev/null; then useradd --system --home-dir /nonexistent --no-create-home --shell /bin/sh "$USER_NAME"
  else adduser -S -H -h /nonexistent -s /bin/sh "$USER_NAME"; fi
fi
# '*' = no password can ever match; unlike a '!' lock it also works for key login on hosts without PAM
usermod -p '*' -s /bin/sh "$USER_NAME"
if id -nG "$USER_NAME" | tr ' ' '\n' | grep -qx docker; then die "$USER_NAME is in the docker group (root-equivalent); remove it first"; fi

install -d -o root -g root -m 0755 "$LIB" "$ETC"
install -o root -g root -m 0755 "$HERE/deploy_gate.py" "$LIB/deploy-gate"
install -o root -g root -m 0755 "$HERE/broker.py" "$LIB/broker"
install -o root -g root -m 0644 "$HERE/approval_schema.py" "$LIB/approval_schema.py"
for f in activate-web-release.sh backup-db.sh verify-public.sh; do install -o root -g root -m 0755 "$DEPLOY_DIR/$f" "$LIB/$f"; done
install -o root -g root -m 0644 "$DEPLOY_DIR/approval-token.sh" "$LIB/approval-token.sh"
[ -f "$ETC/broker.conf" ] || install -o root -g root -m 0644 "$config" "$ETC/broker.conf"
printf 'mushukistan-owner namespaces="mushukistan-deploy-approval" %s\n' "$okey" > "$ETC/allowed_signers.new"
install -o root -g root -m 0644 "$ETC/allowed_signers.new" "$ETC/allowed_signers"; rm -f "$ETC/allowed_signers.new"
printf 'restrict,command="%s/deploy-gate" %s\n' "$LIB" "$dkey" > "$ETC/authorized_keys.new"
install -o root -g root -m 0644 "$ETC/authorized_keys.new" "$ETC/authorized_keys"; rm -f "$ETC/authorized_keys.new"

cat > "$SUDOERS.new" <<EOF
# Managed by install-server.sh (docs/DEPLOYMENT_AUTOMATION.md). One command only; the broker
# validates every argument itself. env_reset drops the caller's environment.
Defaults:$USER_NAME env_reset, !requiretty, secure_path="/usr/sbin:/usr/bin:/sbin:/bin"
$USER_NAME ALL=(root) NOPASSWD: $LIB/broker
EOF
visudo -cf "$SUDOERS.new" >/dev/null || { rm -f "$SUDOERS.new"; die "sudoers validation failed"; }
install -o root -g root -m 0440 "$SUDOERS.new" "$SUDOERS"; rm -f "$SUDOERS.new"

mkdir -p "$(dirname "$SSHD_SNIPPET")"
cat > "$SSHD_SNIPPET" <<EOF
# Managed by install-server.sh (docs/DEPLOYMENT_AUTOMATION.md)
Match User $USER_NAME
    AuthorizedKeysFile $ETC/authorized_keys
    ForceCommand $LIB/deploy-gate
    AuthenticationMethods publickey
    PasswordAuthentication no
    KbdInteractiveAuthentication no
    PermitTTY no
    AllowTcpForwarding no
    AllowStreamLocalForwarding no
    AllowAgentForwarding no
    X11Forwarding no
    PermitTunnel no
    PermitUserRC no
Match all
EOF
chmod 0644 "$SSHD_SNIPPET"
sshd -t || { rm -f "$SSHD_SNIPPET"; die "sshd -t failed; snippet removed, ssh not reloaded"; }
$RELOAD_SSH
install -d -o root -g root -m 0700 /var/lib/mushukistan-deploy
echo "installed. Verify with: ssh -i <deploy key> $USER_NAME@<server> status"
