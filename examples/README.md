# Examples

| Path | What it shows |
| --- | --- |
| [eco/main.bend](eco/main.bend) | The integrated demo, GPU-presented: Ankra's native window and events, Kairo state, Tessra layout (side by side when wide, stacked when narrow), Runika/Syllo/Dithra text, a Mokko button, a PNG decoded by Ocula, an SVG parsed by Splina; Chromi records each frame as a draw list and Voltra draws it. Redraws only when something visible changed. |
| [eco/cpu.bend](eco/cpu.bend) | The same scene on the previous path: CPU raster of the draw list, official window, `XPutImage`, fixed 900x560. For comparison. |
| [eco/reference.bend](eco/reference.bend) | Writes the demo's first frame painted by the CPU reference, at any size (`reference W H`), as `build/eco-reference-WxH.ppm`. |
| [eco/bench_gpu.bend](eco/bench_gpu.bend), [eco/bench_cpu.bend](eco/bench_cpu.bend) | The scene redrawn N times on each path; see [docs/bench.md](../docs/bench.md). |
| [eco/grid.bend](eco/grid.bend) | A text-heavy scene on the same GPU path: the demo's button and an activation counter above N labels ("0001".."N", 10 px) in a 31-column grid (`grid N`, default 1000). Labels are prepared once; an activation re-prepares the counter and every redraw paints every label. Used by the [Eco vs GPUI benchmark](https://github.com/amage-si/eco-bench). |
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
(the layout follows), click the button or use Tab with Space or Enter, then
close it normally: it reports the frames presented and `teardown: 0 native
objects left`.

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
