#!/usr/bin/env bash
# Create (or update) the shared parent cgroup "loadbox" inside the Docker VM.
#
# Every container of the emulated box runs under it (compose `cgroup_parent: loadbox`), so they
# share ONE CPU budget and ONE memory pool, like the services on the production host, which have no
# per-container limits. Values are derived from the read-only capacity inspection (private notes):
#   LOADBOX_CPU_QUOTA   CPU time per 10 ms period, in microseconds. Calibrated so the
#                       remote-inspect.sh capacity benchmark takes as long as on production.
#   LOADBOX_MEM_MIB     memory left for containers on the production host (no swap). Private:
#                       set it in the gitignored loadtest/.secrets/loadbox.env.
# 2800 us / 10 ms = 0.28 of a workstation core = one production core (measured scaling factor).
# Lost when the Docker VM restarts: run.sh calls this before `up`.
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f .secrets/loadbox.env ] && . .secrets/loadbox.env
QUOTA=${LOADBOX_CPU_QUOTA:-2800}
MEM_MIB=${LOADBOX_MEM_MIB:?set LOADBOX_MEM_MIB in loadtest/.secrets/loadbox.env (private sizing)}
MSYS_NO_PATHCONV=1 docker run --rm --privileged --cgroupns=host -v /sys/fs/cgroup:/sys/fs/cgroup \
  alpine:3.20 sh -c "
    mkdir -p /sys/fs/cgroup/loadbox && cd /sys/fs/cgroup/loadbox
    echo '+cpu +cpuset +memory +pids' > cgroup.subtree_control
    echo 0 > cpuset.cpus; echo 0 > cpuset.mems
    echo '$QUOTA 10000' > cpu.max
    echo $((MEM_MIB * 1024 * 1024)) > memory.max
    echo 0 > memory.swap.max
    echo loadbox: cpu.max=\$(cat cpu.max) memory.max=\$(cat memory.max) swap=\$(cat memory.swap.max) cpus=\$(cat cpuset.cpus)"
