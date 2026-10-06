#!/bin/bash
# usage: tools/bench_run.sh <name> <window title> <workdir> <command...>
# Runs a self-terminating benchmark window (see launch.sh), samples its
# VmRSS/VmHWM every 200 ms until it exits, and prints its log with the
# startup time: the first frame's CLOCK_MONOTONIC time minus the launch's.
here="$(cd "$(dirname "$0")" && pwd)"
runs="${RUNS:-$here/../build/runs}"
name=$1; title=$2; dir=$3; shift 3
out="$runs/$name"
"$here/launch.sh" "$name" "$dir" "$@" > /dev/null
P=""
for i in $(seq 1 100); do
  P=$(hyprctl clients -j | python3 -c "
import json,sys
for c in json.load(sys.stdin):
    if c['title'] == sys.argv[1]:
        print(c['pid']); break" "$title")
  [ -n "$P" ] && break; sleep 0.1
done
rss=0; hwm=0
while [ -n "$P" ] && [ -d /proc/$P ]; do
  r=$(awk '/^VmRSS/{print $2}' /proc/$P/status 2>/dev/null); h=$(awk '/^VmHWM/{print $2}' /proc/$P/status 2>/dev/null)
  [ -n "$r" ] && rss=$r; [ -n "$h" ] && hwm=$h
  sleep 0.2
done
for i in $(seq 1 100); do grep -q '^exit=' "$out.log" && break; sleep 0.1; done
cat "$out.log"
launch=$(awk '/^launch_mono_ms/{print $2}' "$out.log")
first=$(grep -o 'mono [0-9]*' "$out.log" | head -1 | awk '{print $2}')
echo "startup (launch to first frame presented): $((first - launch)) ms; last VmRSS $((rss/1024)) MiB, VmHWM $((hwm/1024)) MiB"
