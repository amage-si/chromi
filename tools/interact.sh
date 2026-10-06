#!/bin/bash
# usage: tools/interact.sh <name> <window title> <workdir> <command...>
# Opens a demo (see launch.sh), then sends synthetic X11 input only to its
# window (XSendEvent through Auvia's tools/x11_input.py, beside Chromi): a
# click on the button at ($CLICK_X, $CLICK_Y), Tab, Space, Enter. Captures
# only the demo window after each step, closes it normally, prints its log.
here="$(cd "$(dirname "$0")" && pwd)"
runs="${RUNS:-$here/../build/runs}"
input="python3 -I $here/../../Auvia/tools/x11_input.py"
name=$1; title=$2; dir=$3; shift 3
out="$runs/$name"
"$here/launch.sh" "$name" "$dir" "$@" > /dev/null
info=""
for i in $(seq 1 100); do
  info=$(hyprctl clients -j | python3 -c "
import json,sys
for c in json.load(sys.stdin):
    if c['title'] == sys.argv[1]:
        print(c['address'], c['stableId']); break" "$title")
  [ -n "$info" ] && break; sleep 0.1
done
if [ -z "$info" ]; then echo "window '$title' not found"; cat "$out.log"; exit 1; fi
set -- $info; A=$1; T=$2
sleep 1.5
timeout 5 grim -T "$T" "$out-01-initial.png"
$input "$title" click "${CLICK_X:-95}" "${CLICK_Y:-218}"; sleep 0.6
timeout 5 grim -T "$T" "$out-02-clicked.png"
$input "$title" key Tab; sleep 0.6
timeout 5 grim -T "$T" "$out-03-tab-focus.png"
$input "$title" key space; sleep 0.6
timeout 5 grim -T "$T" "$out-04-space.png"
$input "$title" key Return; sleep 0.6
timeout 5 grim -T "$T" "$out-05-enter.png"
hyprctl dispatch "hl.dsp.window.close({ window = \"address:$A\" })" > /dev/null
for i in $(seq 1 50); do grep -q '^exit=' "$out.log" && break; sleep 0.1; done
cat "$out.log"
