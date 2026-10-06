#!/bin/bash
# usage: tools/drive.sh <name> <window title> <workdir> <command...>
# Opens a demo (see launch.sh), captures only its window (grim -T on its
# toplevel) at the opening size and after each resize by the window manager
# ($SIZES, default "960x630 500x760 1280x480"), then closes it normally and
# prints its log and the capture sizes.
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
set -- $info; A=$1; T=$2
sleep "${SETTLE:-1.0}"
timeout 5 grim -T "$T" "$out-0-open.png"
n=1
for s in ${SIZES:-960x630 500x760 1280x480}; do
  w=${s%x*}; h=${s#*x}
  hyprctl dispatch "hl.dsp.window.resize({ x = $w, y = $h, window = \"address:$A\" })" > /dev/null
  sleep "${SETTLE:-1.0}"
  timeout 5 grim -T "$T" "$out-$n-${w}x${h}.png"; n=$((n+1))
done
hyprctl dispatch "hl.dsp.window.close({ window = \"address:$A\" })" > /dev/null
for i in $(seq 1 50); do grep -q '^exit=' "$out.log" && break; sleep 0.1; done
cat "$out.log"
for f in "$out"-*.png; do magick identify -format '%f %wx%h\n' "$f"; done
