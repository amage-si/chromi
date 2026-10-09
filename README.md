# Chromi

**A 2D renderer written in Bend 2.**

Chromi turns shapes, images, and coverage masks into a composited frame. It is
the drawing layer of the AMAGE UI ecosystem: clipping, color composition, and
rasterization belong here; windows and input belong to
[Ankra](https://github.com/amage-si/ankra), GPU access to
[Voltra](https://github.com/amage-si/voltra).

**Status:** an early renderer with two paths, tested with **Bend 2.0.35**. A
frame is recorded as a **draw list**, or as a **retained frame** of parts that
keeps what did not change; the **CPU reference** paints it into a quadtree
canvas, and the **GPU path** draws it through Voltra, redrawing only what
changed. Both produce the same bytes: every scene and every partial frame in
the GPU checks compared equal to the CPU reference, pixel for pixel. The core
and its native tests depend only on the official Bend `Base` library.

![The integrated demo: text, a button, a text field, a PNG and an SVG, drawn by Chromi and presented by Voltra in an Ankra window.](docs/eco.png)

The capture above is `examples/eco`, captured from its own window only. Text
comes from Runika, Syllo and Dithra; the button and the text field from Mokko
and Kairo, typed text and the clipboard from Ankra; the layout from Tessra;
the PNG is decoded by Ocula and the SVG parsed by Splina.
The capture equals Chromi's CPU reference of the same frame in all 504,000
pixels.

## What works today

- Filled and stroked rectangles, circles, and intersecting rectangular clips.
- **Rounded rectangles and rounded borders** with antialiased corners: 4x4
  samples per pixel on 1/8-pixel geometry, by integer rules shared with
  Voltra's shader.
- Straight RGBA8 source-over composition on an opaque surface.
- **Colour interpolation for animations and gradients** (`mix.bend`):
  `mix_oklab`, `mix_linear` and `mix_srgb` mix two `0xRRGGBBAA` colours at
  `t`, premultiplied as CSS Color 4 does, with exact ends; plus the sRGB
  transfer function and OKLab/OKLCH conversions. Blue to yellow at 0.5 is
  `0x6cabc7ff` in OKLab, `0xbcbcbcff` in linear light and the grey
  `0x808080ff` in sRGB. About 0.3 µs per OKLab mix. Composition is unchanged.
- Row-major RGBA bitmaps and 8-bit coverage masks, with exact-length
  validation, either per call or once (`S.rgba`, `S.coverage`) for pixels drawn
  in every frame.
- Explicit logical-to-physical scaling for geometry and image origins.
- A quadtree canvas that retains uniform regions as single leaves.
- **Draw lists** (`scene.bend`): the canvas's validated calls recorded as
  physical operations, resolved once by the canvas's own rules.
- **CPU reference** (`replay.bend`): a draw list painted into the canvas with
  its blending, as a `Base.Image` or a flat RGBA array.
- **GPU path** (`gpu.bend`): one Voltra quad per operation, bitmaps and masks
  uploaded once into an atlas by key, one draw call per frame.
- **Culling:** an operation that cannot touch a pixel of its clip (outside the
  window or the clip) is not recorded at all; `S.visible` tells an app whether
  a box can show, so it can skip the work behind it.
- **Retained frames** (`frame.bend`): a frame as parts with stable ids (a
  Kairo or Mokko id for a control). The next frame keeps every part whose
  operations (or, for large content, the app's stamp) did not change, with its
  planned GPU quads, and records as damage the boxes where the picture may
  differ. `Gpu.render` redraws only that damage on Voltra's canvas, each
  region with the background and the parts that meet it, scissored, and the
  present names the regions; `R.repaint` does the same on the CPU. A new size
  or the first frame is drawn whole.

How it was verified:

- **82 native checks** (`tests.bend`, no display): geometry, clipping, color,
  masks, invalid input, the final RGB conversion, the draw list (replaying a
  scene equals drawing the same calls on the canvas, operation recording,
  rounded-box quantization, coverage rules, validated pixels), culling, and
  retained frames: a frame equals the draw list of the same calls; an
  unchanged frame damages nothing; stamped parts; joined regions; and
  repainting only the damage equals painting the frame whole for hover, focus,
  a translucent part moved over others, parts removed and added, parts
  reordered and a new size, with a control that differs. Colour mixing:
  sRGB -> OKLab -> sRGB exact on 275,293 colours (and on all 16,777,216 in
  `tests/mix_bench.bend`), 40 mixes per space equal to a float64 reference,
  exact ends, symmetry, premultiplied alpha, blue and yellow.
- **27 GPU checks** (`gpu_tests.bend`, offscreen through Voltra, no display):
  four scenes (fills, borders, clips, translucency, fractional and negative
  edges; rounded boxes and borders; masks and bitmaps through the atlas,
  clipped and partly off the surface; a mixed UI frame) drawn on the GPU and
  compared with the CPU reference: **0 of 64,000 pixels differ** in each.
  Atlas reuse (no second upload of a key) and overflow detection are checked,
  and a negative control confirms the comparison sees a different scene
  (38,364 differing pixels). Retained frames rendered by `Gpu.render`: the
  first frame whole, then hover, a focus ring, a translucent part moved across
  others, a part added, a glyph the atlas has not seen (uploaded inside the
  frame), a mask that does not fit so the atlas starts over inside the frame,
  and the next frame planning its kept parts again, each drawn partly (400 to
  12,000 of 64,000 pixels damaged), a new size drawn whole at 240x150 and back:
  each readback equals the CPU reference of the whole frame (0 differing
  pixels), and a changed frame stripped of its damage is seen to differ
  (6,291 pixels).
- **Integrated demo on a real window** (`examples/eco/main.bend`): captures at
  900x560, 1100x700 and 640x760 (after the window manager resized it, so
  Tessra laid it out again, side by side or stacked) each equal the CPU
  reference at that size (`magick compare -metric AE` 0). Synthetic input sent
  only to its window: a click activated the button once, Space once, Enter
  once. It closed normally with 0 native objects left. With retained frames,
  the demo (Tab, two activations, resizes to 1100x700, 640x760 and 900x560)
  and the 5000-label grid (Tab, two activations) captured at every step equal
  the previous full-redraw binaries pixel for pixel.
- **Editable text field in the demo** (Mokko's `field.bend`, ids 12 and 13:
  the field and its note). On the real window, with keys sent by XTest while
  the window had focus (br-abnt2 keymap) and the pointer by events sent to
  the window alone: Tab reached the field; "Olá, ação!" typed with dead keys;
  a held Backspace repeated; Shift+Home selected; Ctrl+C then `wl-paste`
  printed the text; `wl-copy café` then Ctrl+V inserted it (the paste asked
  the owner and the answer arrived in a later batch); "€" was refused whole
  with the error border and "Character U+20AC cannot be displayed" (that run
  predates Syllo accepting the symbols the font has: € is typed now, and a
  scalar the font lacks, such as U+2615, is what gets refused); a click
  placed the caret and a drag selected; Space in the field typed a space and
  never activated the button, while Space on the button still did. Each
  keystroke was a partial frame of 15,840 pixels (the field's 360x44 box),
  plus the note's box when the message changed; key to presented frame
  0.77 ms median (p90 0.94, 17 keys). Unfocused idle: 0 frames and 0
  main-thread wakeups in 5 s. The first frame equals the CPU reference at
  900x560 (0 differing pixels).
- **Accessible demo** (Auvia, `examples/eco/access.bend`): the demo joins the
  AT-SPI desktop as `amage-eco` with its frame, the button, the status line
  and the field's note (polite live regions) and the text field (an entry
  with `Text` and `EditableText`). Requests from assistive technologies join
  the batch's fold, so a `DoAction` counts as a click and an `InsertText`
  goes through the field like typing. Auvia's libatspi probe passed 27 of 27
  checks on the real window: `SetTextContents`, `InsertText`, `DeleteText`
  (answered in about 5 ms), and a refused U+2615 that returns false and
  changes nothing. Under Orca 50.2, with input sent only to the window, Orca
  spoke the window title, `'Ativar'` `'button.'` on Tab, `'Ativado 1 vez.'`
  on Space, `'Texto livre'` `'entry'` and the placeholder on Tab, the
  refusal message, and the selection. Orca's echo of real typing is not
  verified yet. The loop waits on the window and the bus socket at once
  (Ankra's `watch`): idle for 10 s, 0 frames and 0 main-thread wakeups, the
  same as before Auvia. Window-only input (XSendEvent) typed "Olá, ação!"
  with dead keys; Backspace, Shift+Home, Ctrl+C (the demo took the
  clipboard), a paste of its own text and Enter on the button all
  worked.
- The shape example (`examples/shapes.bend`, official window) still builds;
  `tests/ankra.bend` passes its 2 companion checks.
- **7 text cache checks** (`examples/eco/text_tests.bend`): the demo's text
  (`examples/eco/text.bend`) keeps glyph masks by atlas key and prepared runs
  by (text, size, width) in Voltra's key map; cached runs equal runs prepared
  from scratch bit for bit, repeated texts are hits, a new width is a miss, a
  font with another checksum starts an empty cache, 600 changing texts stay
  within two generations of 256 runs, and runs sharing a hash never mix.
  Rebuilding the demo's model after an activation costs ~0.1 ms of Bend work
  (it was ~4 ms).

## Measurements

The integrated demo's scene at 900x560, redrawn 300 times with the button's
hover state toggling, three runs per path. Method and raw output:
[docs/bench.md](docs/bench.md).

| Path | Wall time per redraw | CPU per redraw | Idle (10 s) | Startup to first frame | Resident memory |
| --- | --- | --- | --- | --- | --- |
| CPU raster + official window (`XPutImage`, 60 Hz) | 72–86 ms | 72–85 ms | ~58 frames/s presented, 75–80 CPU ticks, main thread ~300 wakeups/s | 417–498 ms | 27–35 MiB |
| Draw list + Voltra, FIFO | 5.1–6.7 ms | 1.6–1.7 ms | 0 frames, 2–3 CPU ticks, main thread 0–3 wakeups | 662–888 ms | 96–105 MiB |
| Draw list + Voltra, IMMEDIATE | 1.4–1.5 ms | 1.4–1.5 ms | | | |

Interactive redraws in the demo (scene, planning and GPU submission) took
1–4 ms. The GPU path starts about 0.25–0.45 s later (Vulkan instance, device
and pipeline creation) and holds about 70 MiB more (the NVIDIA driver).

### Partial redraws

The [Eco vs GPUI benchmark](https://github.com/amage-si/eco-bench#after-partial-redraw)
measured the demo and the text grid on X11/XWayland before retained frames
(full redraws) and after them, the second column also with the text cache of
Runika, Syllo and the demo (in the grid an activation prepares only the
counter, so the cache matters little there; in the demo it is most of the
activation's gain). Medians of 3 sessions or more; latency from the key
event sent to the window to the return of `vkQueuePresentKHR`, median / p90:

| Scene | Metric | Before (full redraw) | Retained frames + text cache | GPUI |
| --- | --- | --- | --- | --- |
| Grid, 5000 labels | Activation → presented, ms | 32.9 / 35.4 | 0.6 / 0.8 | 33.2 / 37.4 |
| Grid, 5000 labels | Main-thread CPU per update, ms | 31.2 | 0.55 | 32.5 |
| Grid, 5000 labels | Startup, ms | 483 | 282 | 521 |
| Grid, 5000 labels | Resident memory, MiB | 117 | 93 | 215 |
| Demo | Activation → presented, ms | 7.3 / 9.2 | 0.8 / 1.0 | 5.3 / 8.5 |
| Demo | Key-down → presented, ms | 1.9 / 2.2 | 0.6 / 0.8 | 5.0 / 8.4 |
| Demo | Main-thread CPU per update, ms | 4.62 | 0.74 | 2.58 |

An activation now draws the quads of the parts that changed: 21 in the
5000-label grid (it drew about 20,000) and 26 in the demo (about 235).
Grids of 200 and 1000 labels cost the same as 5000. Labels below the window
are no longer recorded, which shortened the grid's startup. Idle is
unchanged: 0 frames and 0 main-thread wakeups in 10 s.

## Quick start

Requirements: the [Bend 2 toolchain](https://bend-lang.com) and Clang 14 or newer.
The core and its tests need nothing else.

```sh
git clone https://github.com/amage-si/chromi.git Chromi
cd Chromi
export BEND_NO_TELEMETRY=1
bend version
mkdir -p build
bend tests.bend -o build/tests
./build/tests --threads 2 --gpu off
```

The GPU path and the demos need the sibling repositories beside Chromi, with
their capitalized names (Bend imports are case-sensitive), a Vulkan 1.3 driver
and an X11 or XWayland display:

```sh
cd ..
for r in ankra voltra kairo tessra mokko runika syllo dithra ocula splina; do
  git clone https://github.com/amage-si/$r.git "$(echo ${r:0:1} | tr a-z A-Z)${r:1}"
done
cd Chromi
bend gpu_tests.bend -o build/gpu_tests                 # GPU, no display
./build/gpu_tests --threads 2 --gpu off
bend examples/eco/main.bend -o build/eco              # about 85 s, 3.8 GB peak
./build/eco --threads 2 --gpu off                      # run from Chromi/
```

Click the button, use Tab and Space or Enter, Tab again to the text field and
type (dead keys and AltGr work; Ctrl+C/X/V and Shift+Insert use the
clipboard), resize the window, close it normally. The program prints one line
per redraw (with the damaged area) and per input batch (with the field's text
after it). See
[examples/README.md](examples/README.md) for the other examples, the CPU
variant and the benchmarks.

## Draw a frame

```bend
import Base
import ./Chromi/scene.bend as S
import ./Chromi/replay.bend as R
import ./Chromi/geometry.bend as G

def scene() -> S.Scene:
  s = S.new(320, 200, 1.0, 255)
  s = S.round_rect(s, G.Rect{24.0, 24.0, 120.0, 64.0}, 12.0, 4278190335)
  S.border(s, G.Rect{24.0, 24.0, 120.0, 64.0}, 12.0, 2.0, 4294967295)

def image() -> Result<&1, &1, U32 & String, Image>:
  R.image(scene())
```

This records a red rounded rectangle with a white border on an opaque black
surface; `R.image` paints it on the CPU into a `Base.Image` (RGB in the low 24
bits) for the official window. With Voltra, `Gpu.draw(renderer, scene())`
draws the same list on the GPU (`import ./Chromi/gpu.bend as Gpu`).

Colors enter as `U32` values packed `0xRRGGBBAA`. Builders are values: each
call returns the next scene (or canvas); a failure keeps the first error.
The [API reference](docs/api.md) defines coordinate, alpha, mask, rounding and
error contracts. The immediate canvas API (`main.bend`) remains for CPU-only
drawing.

## Current boundaries

- Blending uses encoded sRGB channels, not linear light. Surfaces require
  opaque backgrounds.
- Rectangles and circles have no built-in antialiasing; rounded rectangles
  and borders are antialiased with 16 coverage levels. Supplied coverage
  masks can represent antialiased content.
- Bitmap and mask samples each occupy one physical pixel; scaling an origin
  does not resize the samples. No image resampling, rotation or shadows.
- Circles are not part of the draw list yet (canvas only).
- A damaged region redraws every part that meets it, scissored to the region;
  a part's box is the box of all its operations, so a large part (a whole
  grid of labels) is redrawn whenever damage touches it. Parts are kept by
  comparing operations or by the app's stamps; nothing is cached below a part.
- The atlas is one 1024x1024 texture; when a frame needs more, it starts over
  with that frame's content, and an item larger than the atlas is not drawn.
- Pixel equality between the paths was verified on one GPU and driver.
- Font parsing, text shaping, PNG decoding and SVG parsing are separate
  ecosystem libraries.

## Repository map

| Path | Purpose |
| --- | --- |
| [main.bend](main.bend) | Canvas builder and immediate drawing API (CPU). |
| [scene.bend](scene.bend) | Draw lists: the canvas's calls recorded as physical operations; culling. |
| [frame.bend](frame.bend) | Retained frames: parts kept from frame to frame, damage and regions. |
| [replay.bend](replay.bend) | CPU reference renderer of draw lists and retained frames (whole or only the damage); coverage rules; flat pixels. |
| [gpu.bend](gpu.bend) | GPU renderer of draw lists and retained frames through Voltra (quads, atlas, partial redraws). |
| [geometry.bend](geometry.bend) | Bounds, coordinate conversion, and clip intersections. |
| [color.bend](color.bend) | RGBA channels, source-over blending, and coverage. |
| [mix.bend](mix.bend) | Colour interpolation in OKLab, linear light and sRGB; sRGB transfer, OKLab and OKLCH. |
| [tree.bend](tree.bend) | Quadtree painting, compaction, sampling, and Base image output. |
| [tests.bend](tests.bend) | Native renderer checks (no display, no GPU). |
| [gpu_tests.bend](gpu_tests.bend) | GPU against CPU, pixel by pixel (GPU, no display). |
| [examples/](examples/) | The integrated demo and its CPU variant, benchmarks, the shape scene; `eco/text.bend` and `eco/text_tests.bend` are the demo's cached text. |
| [tests/ankra.bend](tests/ankra.bend) | Two companion checks for the official-window example. |
| [tests/mix_bench.bend](tests/mix_bench.bend) | The full OKLab round trip and the cost of one colour mix. |
| [docs/](docs/) | API and benchmark references. |

## Direction

Next: circles and paths in draw lists, linear-light
blending as an option, and more components through Mokko. Compatibility layers
follow visible Linux progress. These goals do not imply current support.

See [CONTRIBUTING.md](CONTRIBUTING.md) for development rules. The API is
experimental and may change. Licensed under either of [Apache License 2.0](LICENSE-APACHE) or [MIT](LICENSE-MIT), at your option.

## License

Licensed under either of

- Apache License, Version 2.0 ([LICENSE-APACHE](LICENSE-APACHE))
- MIT license ([LICENSE-MIT](LICENSE-MIT))

at your option. Unless you explicitly state otherwise, any contribution
intentionally submitted for inclusion in this work, as defined in the
Apache-2.0 license, shall be dual licensed as above, without any additional
terms or conditions.
