#!/usr/bin/env bash
# Prints the production SSH target without storing it in Git (the repository is public).
# Order: $MUSHUKISTAN_SSH_TARGET, then scripts/deploy/local.env (gitignored), else an error.
#   ssh "$(bash scripts/deploy/ssh-target.sh)" ...          # bash
#   ssh (bash scripts/deploy/ssh-target.sh) ...             # PowerShell
# If neither exists, ask the user for the target; never guess it.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
if [ -n "${MUSHUKISTAN_SSH_TARGET:-}" ]; then printf '%s\n' "$MUSHUKISTAN_SSH_TARGET"; exit 0; fi
if [ -f "$here/local.env" ]; then
  t="$(grep -E '^MUSHUKISTAN_SSH_TARGET=' "$here/local.env" | head -1 | cut -d= -f2- | tr -d '\r"'"'"' ')"
  if [ -n "$t" ]; then printf '%s\n' "$t"; exit 0; fi
fi
echo "ERROR: no SSH target configured. Create scripts/deploy/local.env from local.env.example (gitignored) or ask the user." >&2
exit 1
