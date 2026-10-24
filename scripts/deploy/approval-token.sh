# Sourced by activate-web-release.sh and backup-db.sh (not executed on its own).
#
# check_approval_token FILE -> prints the approval id, or fails.
# The approval broker (scripts/deploy/automation/broker.py) writes a single-use token after it
# has verified the owner's signed approval, and deletes it afterwards. The token stands in for
# the typed confirmation of the manual workflow. It is accepted only if the file and its
# directory are owned by the running user (root on the server, so the restricted deployment
# account can never create one), the file has mode 600, the directory mode 700, and the
# content is a 32-hex approval id.
check_approval_token() {
  local f="$1" dir="${APPROVAL_TOKEN_DIR:-/run/mushukistan-deploy}" me id
  me="$(id -u)"
  case "$f" in
    "$dir"/*.token) ;;
    *) echo "ERROR: approval token must be a .token file directly in $dir" >&2; return 1 ;;
  esac
  case "${f#"$dir"/}" in */*) echo "ERROR: approval token must be directly in $dir" >&2; return 1 ;; esac
  if [ -L "$dir" ] || [ ! -d "$dir" ] || [ "$(stat -c %u "$dir")" != "$me" ] || [ "$(stat -c %a "$dir")" != "700" ]; then
    echo "ERROR: $dir must be a real directory owned by uid $me with mode 700" >&2; return 1
  fi
  if [ -L "$f" ] || [ ! -f "$f" ] || [ "$(stat -c %u "$f")" != "$me" ] || [ "$(stat -c %a "$f")" != "600" ]; then
    echo "ERROR: approval token must be a regular file owned by uid $me with mode 600" >&2; return 1
  fi
  id="$(head -c 64 "$f")"
  [[ "$id" =~ ^[0-9a-f]{32}$ ]] || { echo "ERROR: approval token content is invalid" >&2; return 1; }
  printf '%s\n' "$id"
}
