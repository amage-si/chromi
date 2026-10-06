#!/bin/bash
# usage: tools/idle_run.sh <name> <window title> <workdir> <command...>
# Opens a demo (see launch.sh), lets it settle, samples it for $IDLE
# seconds (default 10) with idle.py while nothing happens, captures only its
# window (grim -T on its toplevel), closes it with the window manager's close
# request and prints the samples and its log.
here="$(cd "$(dirname "$0")" && pwd)"
runs="${RUNS:-$here/../build/runs}"
name=$1; title=$2; dir=$3; shift 3
out="$runs/$name"
"$here/launch.sh" "$name" "$dir" "$@" > /dev/null
info=""
for i in $(seq 1 100); do
  info=$(hyprctl clients -j | python3 -c "
import json,sys
for c in json.load(sys.stdin):
    if c['title'] == sys.argv[1]:
        print(c['address'], c['stableId'], c['pid']); break" "$title")
  [ -n "$info" ] && break; sleep 0.1
done
if [ -z "$info" ]; then echo "window '$title' not found"; cat "$out.log"; exit 1; fi
set -- $info; A=$1; T=$2; P=$3
sleep "${SETTLE:-2}"
before=$(grep -c '^redraw' "$out.log")
python3 -I "$here/idle.py" "$P" "${IDLE:-10}" > "$out.idle"
after=$(grep -c '^redraw' "$out.log")
echo "redraws during the idle interval: $((after - before))" >> "$out.idle"
timeout 5 grim -T "$T" "$out.png"
hyprctl dispatch "hl.dsp.window.close({ window = \"address:$A\" })" > /dev/null
for i in $(seq 1 50); do grep -q '^exit=' "$out.log" && break; sleep 0.1; done
cat "$out.idle"; echo "--- log:"; cat "$out.log"
