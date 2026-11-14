#!/usr/bin/env bash
# Cumulative CPU time (microseconds) used by every service of the emulated box (loadbox cgroup).
MSYS_NO_PATHCONV=1 docker run --rm --privileged --cgroupns=host -v /sys/fs/cgroup:/sys/fs/cgroup:ro \
  alpine:3.20 sh -c "grep usage_usec /sys/fs/cgroup/loadbox/cpu.stat | cut -d' ' -f2"
