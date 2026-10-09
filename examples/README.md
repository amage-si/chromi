# Examples

| Path | What it shows |
| --- | --- |
| [eco/main.bend](eco/main.bend) | The integrated demo, GPU-presented: Ankra's native window and events, Kairo state, Tessra layout (side by side when wide, stacked when narrow), Runika/Syllo/Dithra text, a Mokko button, a Mokko text field (Kairo editing, Ankra text input and CLIPBOARD; text the font cannot show is refused with a message), a PNG decoded by Ocula, an SVG parsed by Splina; Chromi keeps each frame as retained parts (`frame.bend`) and Voltra redraws only what changed, on its canvas. Redraws only when something visible changed; a click lays out only the status line again, a keystroke redraws only the field (and its note when the message changes). The button and the field animate through Mokko's `anim.bend` (Kinera motions, OKLab colour mixing): hover and press fades with a 1-unit press sink, focus rings that fade and grow in, the field border fading to the error colour, and a caret that blinks for about 10 s after the last edit, then stays solid. While something moves the loop draws on the monitor's refresh grid (Ankra's `animate`) and each frame redraws only the moving control; once everything rests it waits with no deadline again. `ECO_REDUCE_MOTION=1` makes every transition instant and the caret solid (the desktop's reduce-motion setting is not read yet). Accessible through Auvia ([eco/access.bend](eco/access.bend)): screen readers see the button, the status line, the text field and its note, and their requests go through Kairo and the field like user input; at rest the loop wakes only for the window or the accessibility bus, never on a timer. `AUVIA_LOG=1` prints every AT-SPI call and event. |
| [eco/cpu.bend](eco/cpu.bend) | The same scene on the previous path: CPU raster of the draw list, official window, `XPutImage`, fixed 900x560. For comparison. |
| [eco/reference.bend](eco/reference.bend) | Writes the demo's first frame painted by the CPU reference, at any size (`reference W H`), as `build/eco-reference-WxH.ppm`. |
| [eco/bench_gpu.bend](eco/bench_gpu.bend), [eco/bench_cpu.bend](eco/bench_cpu.bend) | The scene redrawn N times on each path; see [docs/bench.md](../docs/bench.md). |
| [eco/grid.bend](eco/grid.bend) | A text-heavy scene on the same GPU path: the demo's button and an activation counter above N labels ("0001".."N", 10 px) in a 31-column grid (`grid N`, default 1000). Labels are prepared once; an activation re-prepares the counter. The labels are one stamped part recorded once per window size (labels outside the window are skipped), so an activation redraws the button and the counter only. Used by the [Eco vs GPUI benchmark](https://github.com/amage-si/eco-bench). |
| [shapes.bend](shapes.bend) | The canvas with Ankra's official-runtime loop: rectangles, borders, circles, alpha, clipping, retained frames; a click changes the accent color. |
| [text.bend](text.bend) | Text runs painted on the canvas (used by `integrated.bend`). |
| [integrated.bend](integrated.bend) | The earlier CPU-only text and button demo in the official window. |

The `eco` programs need the sibling repositories beside Chromi, with their
capitalized names: Ankra, Voltra, Kairo, Tessra, Mokko, Runika, Syllo,
Dithra, Ocula, Splina. Run them from the Chromi directory (the SVG path is
`../Splina/fixtures/heart-fill.svg`; the PNG is `/usr/share/pixmaps/kitty.png`
and the font `/usr/share/fonts/liberation/LiberationSans-Regular.ttf`).

```sh
export BEND_NO_TELEMETRY=1
mkdir -p build
bend examples/eco/main.bend -o build/eco     # one compilation unit: about 85 s, 3.8 GB peak
./build/eco --threads 2 --gpu off
```

The demo prints one line per input batch and per redraw. Resize the window
(the layout follows), click the button or use Tab with Space or Enter, Tab to
the text field and type, copy and paste, then close it normally: it reports the frames presented and `teardown: 0 native
objects left`. With an AT-SPI bus (`at-spi2-core`) the demo registers as
`amage-eco`; run Orca, or Auvia's `tools/atspi_probe.py --app amage-eco
--button Ativar --label-prefix "Clique no botão|Ativado" --field "Texto livre"
--field-seed olá --out probe.json`, against it. Without a bus it runs the
same, offline.

Motion, measured on this machine (Bend 2.0.36, 900x560 on the 120 Hz
HDMI-A-1 output's visible workspace, without keyboard focus, input sent with
XSendEvent, present times from eco-bench's present-log layer, three runs):

| | Result |
| --- | --- |
| Hover in, hover out | 32 frames each (~265 ms); present interval p50 8.5-8.6 ms, p99 8.8-9.7 ms; 0 dropped |
| Main-thread CPU per animated frame | 0.55-0.71 ms (update, frame recording, GPU submission and the log line) |
| Damage per animated frame | the button's bounds only (3510 px) while it animates; the field's (15840 px) while its ring or caret does |
| After the motion settles | 0 frames and 0 main-thread wakeups (3 s windows), also once the caret stops blinking |
| Caret blink | ~390 frames over its 10 cycles (frames only during the 150 ms fades, a timer between them) |

About a third of the hover frames change no pixel (the colour's last steps
are under one byte); they still cost a frame each.

`shapes.bend` and `tests/ankra.bend` use only Ankra's official-runtime
backend (`main.bend`):

```sh
bend tests/ankra.bend -o build/ankra-checks
./build/ankra-checks --threads 2 --gpu off
bend examples/shapes.bend -o build/shapes
./build/shapes --threads 2 --gpu off
```

The paths under `_pending/` are earlier experiments, preserved; they are not
a working integration.
