#!/usr/bin/env bash
# Run the broker/gate/schema/CLI unit tests in a disposable Alpine container as a normal user.
# The scripts are streamed in with tar (a Windows bind mount would break POSIX permissions).
#   bash scripts/deploy/automation/run_unit_tests.sh
set -euo pipefail
cd "$(dirname "$0")/../../.."
tar -c scripts/deploy | MSYS_NO_PATHCONV=1 docker run --rm -i --memory 512m alpine:3.20 sh -c '
  set -e
  apk add --no-cache python3 bash openssh-keygen coreutils >/dev/null
  adduser -D tester
  mkdir /work && tar -x -C /work && chown -R tester /work
  su tester -c "cd /work && python3 -m unittest discover -s scripts/deploy/automation/tests -v" 2>&1'
