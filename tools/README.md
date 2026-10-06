# Tools

Validation helpers for running Chromi's demos on a real desktop (Hyprland
0.56 with XWayland). They are not part of Chromi.

| Script | Purpose |
| --- | --- |
| `launch.sh` | Starts a program through Hyprland on workspace 1, floating, without taking keyboard focus; logs a `CLOCK_MONOTONIC` launch time, the output and the exit status to `build/runs/<name>.log`. |
| `drive.sh` | Captures only the program's window (`grim -T` on its toplevel) at its opening size and after resizes by the window manager, then closes it normally. |
| `interact.sh` | Sends synthetic X11 input to the window only (Auvia's `tools/x11_input.py`): a click, Tab, Space, Enter; captures after each. |
| `idle_run.sh`, `idle.py` | Samples an idle program: CPU ticks, each thread's context switches, resident memory, redraws in the interval. |
| `bench_run.sh` | Runs a self-terminating benchmark, samples its memory, reports startup to first frame. |

Captures are always of the program's own window, never of a screen region.
Results and the method are in [docs/bench.md](../docs/bench.md).
