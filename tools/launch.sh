#!/bin/bash
# usage: tools/launch.sh <name> <workdir> <command...>     (validation only)
# Starts the command through Hyprland on workspace 1, floating, without
# taking keyboard focus, so tests do not disturb the desktop. Its output,
# a CLOCK_MONOTONIC launch timestamp and its exit status go to
# $RUNS/<name>.log (RUNS defaults to build/runs beside this script).
here="$(cd "$(dirname "$0")" && pwd)"
runs="${RUNS:-$here/../build/runs}"
mkdir -p "$runs"
name=$1; dir=$2; shift 2
run="$runs/$name.sh"
log="$runs/$name.log"
{
  echo '#!/bin/bash'
  echo "cd $(printf %q "$dir")"
  echo "python3 -I -c 'import time; print(\"launch_mono_ms\", int(time.monotonic() * 1000))' > $(printf %q "$log")"
  printf '%q ' "$@"; echo ">> $(printf %q "$log") 2>&1"
  echo "echo exit=\$? >> $(printf %q "$log")"
} > "$run"
chmod +x "$run"
: > "$log"
hyprctl eval "hl.exec_cmd('$run', { workspace = '1 silent', float = true, no_initial_focus = true })"
