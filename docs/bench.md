# GPU path against the CPU path

The integrated demo's scene (`examples/eco`: text, a Mokko button, a PNG and
an SVG, 235 draw-list operations at 900x560) on two paths:

- **CPU/`XPutImage`:** Chromi paints the draw list into its quadtree canvas
  (`replay.bend`), and the official runtime window (Ankra's `main.bend`)
  presents the image with `XPutImage`, paced by the runtime at 60 Hz.
- **GPU:** Chromi records the draw list and Voltra draws it (one quad per
  operation, atlas uploads once per key, one draw call) into Ankra's native
  window.

Both use the same model, layout, text, media and Kairo button code.

## Method

Programs (run from the Chromi directory, siblings beside it):

```sh
bend examples/eco/bench_gpu.bend -o build/bench_gpu
bend examples/eco/bench_cpu.bend -o build/bench_cpu
bend examples/eco/main.bend -o build/eco          # GPU demo
bend examples/eco/cpu.bend -o build/eco-cpu       # CPU demo
```

- **Frame time and CPU per frame:** each bench redraws the scene 300 times,
  moving Kairo's pointer on and off the button every frame, so the hover
  state changes and the whole frame is rebuilt (GPU: draw list, plan, upload
  of nothing new, draw, present; CPU: draw list, quadtree raster, `Base.Image`,
  `XPutImage`). Wall time from `IO.now`; CPU time of the whole process (user +
  system, all threads) from `/proc/self/stat` in 10 ms ticks, before and after
  the 300 frames, so startup and the first frame are excluded. GPU runs poll
  Ankra's events once per frame; `novsync` presents with IMMEDIATE.
- **Startup:** from a `CLOCK_MONOTONIC` timestamp taken by the launcher
  right before starting the program to the program's own `CLOCK_MONOTONIC`
  time after its first frame was handed to the display server (GPU: after
  `vkQueuePresentKHR`; CPU: at the first tick, after the first
  `Window.frame`). Includes loading the font, decoding the PNG, parsing and
  rasterizing the SVG, text layout and, on the GPU path, Vulkan setup.
- **Resident memory:** `VmRSS`/`VmHWM` from `/proc/<pid>/status`, sampled
  every 200 ms during the bench and at the end of the idle interval.
- **Idle:** the demo opened, settled for 2 s, then sampled for 10 s without
  input by `tools/idle.py`: process CPU ticks, and each thread's voluntary
  and involuntary context switches (a sleeping thread that wakes counts one).
  Redraws during the interval are counted from the demo's own log.

The tools are in [tools/](../tools/): `launch.sh` starts a program through
Hyprland on a workspace of the laptop display, floating and without taking
keyboard focus; `bench_run.sh` and `idle_run.sh` run and sample it;
`drive.sh` and `interact.sh` resize it or send synthetic input to its window
only. Every capture is of the demo window alone (`grim -T`).

```sh
for i in 1 2 3; do
  tools/bench_run.sh bench-gpu-fifo-$i "AMAGE Eco - GPU bench" "$PWD" ./build/bench_gpu 300 --threads 2 --gpu off
  tools/bench_run.sh bench-gpu-imm-$i "AMAGE Eco - GPU bench" "$PWD" ./build/bench_gpu 300 novsync --threads 2 --gpu off
  tools/bench_run.sh bench-cpu-$i "AMAGE Eco - CPU bench" "$PWD" ./build/bench_cpu 300 --threads 2 --gpu off
  tools/idle_run.sh idle-gpu-$i "AMAGE Eco - Ankra, Voltra, Chromi" "$PWD" ./build/eco --threads 2 --gpu off
  tools/idle_run.sh idle-cpu-$i "AMAGE Eco - CPU path" "$PWD" ./build/eco-cpu --threads 2 --gpu off
done
```

## Results

Machine: NVIDIA GeForce RTX 3050 Laptop GPU, driver 610.57.04, Vulkan 1.4.341,
Hyprland 0.56.2 with XWayland, two 1920x1080 displays at 120 Hz, 16 cores,
Bend 2.0.35, `--threads 2`. Three runs each, 2026-10-06.

| Path | Wall per redraw | CPU per redraw | Startup | VmRSS |
| --- | --- | --- | --- | --- |
| CPU/`XPutImage` | 86.0 / 80.5 / 72.2 ms | 85.4 / 80.0 / 71.8 ms | 417 / 498 / 445 ms | 33–34 MiB |
| GPU, FIFO | 6.7 / 5.1 / 5.4 ms | 1.70 / 1.57 / 1.60 ms | 736 / 730 / 750 ms | 105 MiB |
| GPU, IMMEDIATE | 1.39 / 1.40 / 1.53 ms | 1.40 / 1.40 / 1.53 ms | 662 / 680 / 888 ms | 105 MiB |

| Idle, 10 s | Frames presented | CPU ticks | Main thread wakeups | VmRSS |
| --- | --- | --- | --- | --- |
| CPU/`XPutImage` demo | ~576 (600 frame cycles per 10.4 s) | 78 / 80 / 75 | 3154 / 3021 / 3136 | 27–30 MiB |
| GPU demo | 0 / 0 / 0 | 2 / 3 / 2 | 3 / 0 / 0 | 96 MiB |

Reading the tables:

- The GPU path spends about 1.4–1.7 ms of CPU per redraw against 72–85 ms:
  the CPU path's cost is the quadtree raster of the whole 900x560 frame in
  Bend; the GPU path's is building the draw list (about 1.2 ms in Bend,
  dominated by text and the button), planning it against the atlas (about
  0.8 ms) and submitting it.
- Under FIFO on XWayland, redraws were paced at 150–195 per second on this
  120 Hz machine; IMMEDIATE shows the cost of a frame itself.
- The GPU path starts 0.25–0.45 s later (Vulkan instance, device, pipeline
  and atlas creation) and holds about 70 MiB more (the NVIDIA driver).
- Idle: the GPU demo presents nothing and its main thread sleeps; the CPU
  demo keeps presenting the retained image about 58 times per second (the
  official window has no wait-for-events mode). NVIDIA driver threads in the
  GPU process wake on their own: `[vkrt]` about 10 times per second,
  `[vkps]` about 4, and one unnamed thread about 100.

Before draw-list pixels were validated once and glyphs pre-placed (same day),
the GPU bench measured 3.7–4.5 ms of CPU per redraw; a profile showed the
per-frame validation of the 256x256 PNG (65,536 samples) dominating.

A later idle sample (not in the table) recorded 3 redraws and 84 main-thread
wakeups per second because someone used the window during the interval: its
log shows a focus-in, 817 pointer motions and clicks. Samples with input are
not idle and were discarded.

## Raw output

Bench logs (`launch_mono_ms` is the launcher's timestamp):

```text
## bench-gpu-fifo-1
launch_mono_ms 67337914
first frame presented 732 ms after main started (mono 67338650)
gpu FIFO: 300 redraws in 2003 ms (6676 us/frame), 51 CPU ticks, 1700 us CPU/frame
teardown: 0 native objects left; driver messages: 0 warnings, 0 errors
## bench-gpu-fifo-2
launch_mono_ms 67340884
first frame presented 726 ms after main started (mono 67341614)
gpu FIFO: 300 redraws in 1536 ms (5120 us/frame), 47 CPU ticks, 1566 us CPU/frame
teardown: 0 native objects left; driver messages: 0 warnings, 0 errors
## bench-gpu-fifo-3
launch_mono_ms 67343324
first frame presented 746 ms after main started (mono 67344074)
gpu FIFO: 300 redraws in 1611 ms (5370 us/frame), 48 CPU ticks, 1600 us CPU/frame
teardown: 0 native objects left; driver messages: 0 warnings, 0 errors
## bench-gpu-imm-1
launch_mono_ms 67345801
first frame presented 658 ms after main started (mono 67346463)
gpu IMMEDIATE: 300 redraws in 417 ms (1390 us/frame), 42 CPU ticks, 1400 us CPU/frame
teardown: 0 native objects left; driver messages: 0 warnings, 0 errors
## bench-gpu-imm-2
launch_mono_ms 67346992
first frame presented 676 ms after main started (mono 67347672)
gpu IMMEDIATE: 300 redraws in 420 ms (1400 us/frame), 42 CPU ticks, 1400 us CPU/frame
teardown: 0 native objects left; driver messages: 0 warnings, 0 errors
## bench-gpu-imm-3
launch_mono_ms 67348395
first frame presented 884 ms after main started (mono 67349283)
gpu IMMEDIATE: 300 redraws in 459 ms (1530 us/frame), 46 CPU ticks, 1533 us CPU/frame
teardown: 0 native objects left; driver messages: 0 warnings, 0 errors
## bench-cpu-1
launch_mono_ms 67356731
first frame presented 414 ms after main started (mono 67357148)
cpu XPutImage: 300 redraws in 25790 ms (85966 us/frame), 2562 CPU ticks, 85400 us CPU/frame
## bench-cpu-2
launch_mono_ms 67383042
first frame presented 490 ms after main started (mono 67383540)
cpu XPutImage: 300 redraws in 24135 ms (80450 us/frame), 2400 CPU ticks, 80000 us CPU/frame
## bench-cpu-3
launch_mono_ms 67407841
first frame presented 429 ms after main started (mono 67408286)
cpu XPutImage: 300 redraws in 21659 ms (72196 us/frame), 2155 CPU ticks, 71833 us CPU/frame
```

`bench_run.sh` reported `VmRSS 105 MiB, VmHWM 105 MiB` for every GPU run
(one IMMEDIATE run ended at 89 MiB resident, 105 MiB peak) and 33–34 MiB for
the CPU runs.

Idle samples:

```text
## idle-gpu-1
idle 10 s: 2 CPU ticks (10 ms each); VmRSS 95.7 MiB, VmHWM 95.7 MiB
  thread 359745 (main) eco: 3 voluntary, 0 involuntary switches (0.3/s)
  thread 359746 eco: 0 voluntary, 0 involuntary switches (0.0/s)
  thread 359901 eco: 5 voluntary, 0 involuntary switches (0.5/s)
  thread 359902 [vkcf] Analysis: 0 voluntary, 0 involuntary switches (0.0/s)
  thread 359904 [vkrt] Analysis: 100 voluntary, 0 involuntary switches (10.0/s)
  thread 359905 [vkps] Update: 40 voluntary, 0 involuntary switches (4.0/s)
  thread 359907 eco: 994 voluntary, 3 involuntary switches (99.7/s)
redraws during the idle interval: 0
## idle-gpu-2
idle 10 s: 3 CPU ticks (10 ms each); VmRSS 95.7 MiB, VmHWM 95.7 MiB
  thread 361422 (main) eco: 0 voluntary, 0 involuntary switches (0.0/s)
  thread 361423 eco: 0 voluntary, 0 involuntary switches (0.0/s)
  thread 361495 eco: 5 voluntary, 0 involuntary switches (0.5/s)
  thread 361496 [vkcf] Analysis: 0 voluntary, 0 involuntary switches (0.0/s)
  thread 361504 [vkrt] Analysis: 100 voluntary, 1 involuntary switches (10.1/s)
  thread 361506 [vkps] Update: 40 voluntary, 0 involuntary switches (4.0/s)
  thread 361508 eco: 994 voluntary, 2 involuntary switches (99.6/s)
redraws during the idle interval: 0
## idle-gpu-3
idle 10 s: 2 CPU ticks (10 ms each); VmRSS 95.7 MiB, VmHWM 95.7 MiB
  thread 363422 (main) eco: 0 voluntary, 0 involuntary switches (0.0/s)
  thread 363424 eco: 0 voluntary, 0 involuntary switches (0.0/s)
  thread 363500 eco: 5 voluntary, 0 involuntary switches (0.5/s)
  thread 363501 [vkcf] Analysis: 0 voluntary, 0 involuntary switches (0.0/s)
  thread 363503 [vkrt] Analysis: 100 voluntary, 0 involuntary switches (10.0/s)
  thread 363504 [vkps] Update: 40 voluntary, 1 involuntary switches (4.1/s)
  thread 363513 eco: 992 voluntary, 1 involuntary switches (99.3/s)
redraws during the idle interval: 0
## idle-cpu-1 (log: "frame cycles: 600 at 10405 ms")
idle 10 s: 78 CPU ticks (10 ms each); VmRSS 27.4 MiB, VmHWM 27.4 MiB
  thread 365832 (main) eco-cpu: 3062 voluntary, 92 involuntary switches (315.4/s)
  thread 365833 eco-cpu: 0 voluntary, 0 involuntary switches (0.0/s)
redraws during the idle interval: 0
## idle-cpu-2 (log: "frame cycles: 600 at 10413 ms")
idle 10 s: 80 CPU ticks (10 ms each); VmRSS 29.6 MiB, VmHWM 29.6 MiB
  thread 367492 (main) eco-cpu: 2890 voluntary, 131 involuntary switches (302.1/s)
  thread 367493 eco-cpu: 0 voluntary, 0 involuntary switches (0.0/s)
redraws during the idle interval: 0
## idle-cpu-3 (log: "frame cycles: 600 at 10423 ms")
idle 10 s: 75 CPU ticks (10 ms each); VmRSS 28.2 MiB, VmHWM 28.2 MiB
  thread 369073 (main) eco-cpu: 3004 voluntary, 132 involuntary switches (313.6/s)
  thread 369074 eco-cpu: 0 voluntary, 0 involuntary switches (0.0/s)
redraws during the idle interval: 0
```

For the CPU demo, "redraws" counts content changes; it presents on every
frame cycle regardless (600 cycles in about 10.4 s).

## Exactness

`examples/eco/reference.bend W H` writes the CPU reference of the first frame
at any size. Captures of the GPU demo's window at 900x560, 1100x700, 640x760
and back at 900x560 (after the window manager resized it each time) equal the
references in every pixel (`magick compare -metric AE` 0). The CPU demo's
capture at 900x560 equals the same reference.
