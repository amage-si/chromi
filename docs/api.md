# Chromi API

The core renderer imports only `Base` and modules in this repository; the GPU
path (`gpu.bend`) also imports Voltra. The `Canvas` builder is affine.
Operations consume a canvas and return the next canvas; a failure preserves
the first error through subsequent operations.

## Surface and geometry

| Function | Contract |
| --- | --- |
| `new(width, height, scale, background)` | Physical `U32` dimensions in 1..4096; finite `F32` scale in (0, 16]; background alpha must be 255. |
| `fill_rect(canvas, G.Rect{x, y, width, height}, rgba)` | Logical `F32` geometry, nonnegative dimensions, pixel-center coverage, exclusive right/bottom edges. |
| `stroke_rect(canvas, rect, thickness, rgba)` | Inward border without repeated corner composition; thickness must be finite and nonnegative. |
| `circle(canvas, cx, cy, radius, rgba)` | Horizontal spans without built-in antialiasing; radius must be finite and nonnegative. |
| `clip_rect(canvas, rect)` | Intersects the current clip; does not create a clip stack. |
| `reset_clip(canvas)` | Restores the full surface clip. |

The origin is at the top left; y increases downward. Drawing coordinates are
bounded to plus or minus 1,048,576 and reject NaN/infinity. Clipping precedes
conversion to unsigned coordinates. Use the validated API; constructing internal
`Canvas` fields directly bypasses those checks.

## Pixels and coverage

| Function | Contract |
| --- | --- |
| `blit_rgba(canvas, x, y, width, height, pixels)` | Row-major `List<&2, U32>`, exactly width times height elements, straight RGBA8 packed `0xRRGGBBAA`. |
| `blit_mask(canvas, x, y, width, height, coverage, ink)` | Same row-major layout; coverage is `U32` in 0..255 and multiplies ink alpha with rounding. |
| `pixel(canvas, x, y)` | Diagnostic physical-pixel read; consumes the canvas and returns RGBA in `Some`, or `None` for a failed canvas/out-of-bounds location. |
| `finish(canvas)` | Consumes the canvas and returns `Result<&1, &1, U32 & String, Image>`. A failure returns code 22 and the original message. |

Bitmap/mask origins are logical: each is mapped with `floor(origin * scale)`.
Each sample occupies one physical pixel; there is no implicit image resizing.
Rasterize text or paths at the intended physical size before supplying a mask.
Zero-area input with an empty list is accepted. Dimensions are bounded to 4096
per axis. Input length and mask coverage are checked before painting.

Colors use straight alpha and source-over composition onto an opaque destination.
Channel blending happens in encoded sRGB with integer rounding. `finish` visits
the quadtree and converts RGBA leaves to the official `Base.Image` RGB format
(`0xRRGGBB`). It does not open a window or send work to a GPU.

## Storage and cost

The surface occupies a square quadtree whose side is the next power of two at
least as large as either dimension. The active clip restricts painting to the
requested width and height. Uniform regions remain single `Pix` leaves; four
equal leaves compact to one. An opaque fill can replace an entire subtree.

Work depends on the number of nodes touched. Bitmap validation is linear in
input length; per-sample painting can cost up to the tree depth per sample.
The maximum depth is 12 for supported surfaces. No constant-time rendering or
partial native upload guarantee is made.

`geometry.bend`, `color.bend`, and `tree.bend` expose implementation helpers
because Bend modules have no public/private export boundary here. Applications
should use `main.bend` and `G.Rect` rather than depend on tree internals.

## Colour interpolation (`mix.bend`)

For animations and gradients: a colour between two others, computed every
frame. Colours are `0xRRGGBBAA`, sRGB-encoded, straight alpha, as everywhere
in Chromi. This does not change composition, which stays in encoded sRGB.

| Function | Contract |
| --- | --- |
| `M.mix_oklab(a, b, t)` | `U32`: `a` to `b` at `t` in OKLab. The perceptual choice: even lightness steps, hue kept (blue to yellow passes through a light blue-green, not grey). |
| `M.mix_linear(a, b, t)` | The same in linear-light sRGB (physical light: what a blur or a cross-fade of light does). |
| `M.mix_srgb(a, b, t)` | The same in encoded sRGB bytes, as a plain lerp; for comparison and for matching other tools. |
| `M.to_linear(v)`, `M.to_srgb(v)` | The exact sRGB transfer function (IEC 61966-2-1) on `F32` 0..1: `v / 12.92` up to 0.04045, else `((v + 0.055) / 1.055)^2.4`; back: `12.92 v` up to 0.0031308, else `1.055 v^(1/2.4) - 0.055`, clamped to 0..1 (NaN gives 0). |
| `M.byte_to_linear(c)`, `M.linear_to_byte(v)` | A channel byte to linear light; linear light to a byte, clamped and rounded to nearest. |
| `M.rgb(c)`, `M.rgba(v, alpha)` | `0xRRGGBBAA` to `M.Rgb{r, g, b}` in linear light, and back with an alpha byte. |
| `M.oklab(v)`, `M.oklab_to_linear(lab)` | Linear sRGB to `M.Lab{l, a, b}` and back with Björn Ottosson's matrices; back may leave 0..1 outside the gamut. |
| `M.of_rgba(c)`, `M.to_rgba(lab, alpha)` | `0xRRGGBBAA` to OKLab (alpha dropped) and back (clamped to the gamut per channel, rounded). |
| `M.oklch(lab)`, `M.oklch_to_oklab(lch)` | `M.Lch{l, c, h}`: chroma `hypot(a, b)`, hue `atan2(b, a)` in radians. |

Rules of the three mixes:

- **Ends.** `t <= 0` (and NaN) answers `a` exactly and `t >= 1` answers `b`
  exactly, without conversion: an animation lands on its colour. `t` is
  clamped, so a spring's overshoot does not extrapolate colours.
- **Alpha** is interpolated linearly, `round(aa + (ab - aa) t)`.
- **Colour is premultiplied**, as CSS Color 4 interpolates: each end counts in
  proportion to its alpha, in the interpolation space. Straight
  interpolation would fade red to transparent black through dark,
  half-visible reds (a dark fringe); premultiplied, a transparent end lends no
  colour and red stays red while it fades (`mix(0xff0000ff, 0x00000000, 0.5)`
  is `0xff000080`). The colour weight of `b` is `t ab / ((1 - t) aa + t ab)`,
  which is `t` when the alphas are equal (also both 0), so opaque colours mix
  as a plain lerp.
- **Rounding.** OKLab and linear results are clamped per channel to the gamut
  and rounded to the nearest byte; sRGB mixes round the interpolated byte.

Blue (`0x0000ffff`) to yellow (`0xffff00ff`) at 0.5:

| Space | Result |
| --- | --- |
| OKLab | `0x6cabc7ff` (light blue-green) |
| linear light | `0xbcbcbcff` (light grey) |
| sRGB | `0x808080ff` (the muddy grey) |

**Accuracy** (all in `F32`; cube roots and powers are `F32.pow`):
sRGB -> OKLab -> sRGB gives every one of the 16,777,216 opaque colours back
exactly (`tests/mix_bench.bend`; `tests.bend` checks every 61st and every
grey). Against an independent float64 reference, 100,000 random mixes per
space were within 1 of every channel (0.2% off by 1, ties of rounding); the
40 mixes kept in `tests.bend` are exact.

**Cost** per call on Ian's machine (Bend 2.0.36, `-O3`, one core): about 0.26
to 0.4 µs for `mix_oklab` (15 `pow`), 0.13 to 0.2 µs for `mix_linear` and 0.02
µs for `mix_srgb`. An animated colour is one call per frame.

## Draw lists (`scene.bend`)

A `Scene` records the same validated calls as the canvas, resolved to
physical operations by the canvas's own rules, instead of painting them.
It is `Data`; each call returns the next scene; a failure keeps the first
error.

| Function | Contract |
| --- | --- |
| `S.new(width, height, scale, background)` | As `new`. |
| `S.fill_rect(s, rect, rgba)`, `S.stroke_rect(s, rect, thickness, rgba)`, `S.clip_rect(s, rect)`, `S.reset_clip(s)` | As the canvas calls. A fill records its pixel-center box already intersected with the clip; empty or fully transparent fills record nothing. |
| `S.round_rect(s, rect, radius, rgba)` | A rectangle with corners rounded by `radius` (logical units). The box and radius are quantized to 1/8 physical pixel (`round(v * scale * 8)`); the radius is clamped to half the shorter side. |
| `S.border(s, rect, radius, width, rgba)` | The inward border of such a rectangle, `width` logical units wide (clamped the same way); inner corners rounded by `max(radius - width, 0)`. A border thinner than 1/8 pixel records nothing. |
| `S.blit_rgba(s, key, x, y, w, h, pixels)`, `S.blit_mask(s, key, x, y, w, h, coverage, ink)` | As the canvas blits, validating the data on every call. `key` names these pixels for the GPU atlas: one key must always mean the same pixels. |
| `S.rgba(key, w, h, pixels)`, `S.coverage(key, w, h, coverage)` | `Result<&2, &2, String, Pixels>`: data validated once (length, coverage range, 4096 bound). |
| `S.draw(s, pixels, x, y, ink)` | Validated pixels at a logical origin floored to a physical pixel; masks in `ink`. No per-call pass over the samples. |
| `S.ops(s)` | `Result<&1, &1, U32 & String, List<&2, Op>>`: the operations in drawing order, or the first error. |
| `S.size(s)`, `S.background(s)`, `S.count(s)` | Surface size, background, number of operations. |
| `S.visible(s, rect)` | Whether anything drawn within `rect` (logical units) could show: the whole pixels it covers meet the current clip. For skipping work whose operations would be culled anyway (laying out or painting a label far below the window). An invalid rectangle answers True. |
| `S.same_ops(a, b)`, `S.bounds(ops, acc)`, `S.op_box(op)` | Whether two draw lists draw the same (bitmaps and masks compared by key); the surface pixels operations can touch. |

**Culling.** A bitmap, mask or rounded box that cannot touch a pixel of its
clip (outside the surface or the clip, or empty) is not recorded, like an
empty fill. Such an operation painted nothing, so the picture is the same;
content far outside the window then costs no planning, upload or drawing.

`Op`: `Fill{box, color}`, `Round{x0, y0, x1, y1, radius, border, color, clip}`
(1/8-pixel signed coordinates; border 0 fills), `Bitmap{key, x, y, width,
height, pixels, clip}`, `Mask{key, x, y, width, height, coverage, ink, clip}`
(physical signed origins; clip boxes in physical pixels).

## Retained frames (`frame.bend`)

A `F.Frame` is a frame as parts in drawing order. Each `F.Part{id, stamp,
bounds, ops, cache}` has a stable `id` chosen by the app (the Kairo or Mokko
id of a control, the layout id of a block), its draw list, the box of
surface pixels that list can touch, and what a renderer derived from it
(`cache`: `Unplanned{}` or `Planned{epoch, quads, first}`: the GPU path's
quads, at `[first, first + quads)` of Voltra's store). Each part is a separate draw list starting with the whole
surface as its clip. A frame is built from the last one:

| Function | Contract |
| --- | --- |
| `F.none()` | The frame before the first; the next one is drawn whole. |
| `F.begin(last, w, h, scale, background)` | A builder (`F.Build`). Parts of `last` are kept only on the same surface (size, scale, background); otherwise every part is recorded again and the frame is whole. Damage `last` still carried (it was never drawn) carries over. |
| `F.part(b, id, draw)` | `draw: S.Scene -> S.Scene` records the part into an empty scene of the surface, every frame. When the last frame's part with this id recorded the same operations (`S.same_ops`), that part is kept, cache included, and nothing is damaged; otherwise the new part replaces it and both boxes are damaged. |
| `F.stamped(b, id, stamp, draw)` | Records the part only when its `stamp` differs from the kept part's (or no part has the id): the app promises that an equal stamp draws the same. For large content that rarely changes. |
| `F.end(b)` | The frame. Parts of the last frame not met again were removed: their boxes are damaged. A part whose scene failed fails the frame (`F.Failed{message}`). |
| `F.blank(b)` | An empty scene of the builder's surface. |
| `F.regions(f)` | The damage within the surface, boxes joined where they meet (they may still overlap: a pixel redrawn twice gets the same value). Empty when nothing changed. |
| `F.whole(f)`, `F.damage(f)`, `F.parts(f)`, `F.size(f)`, `F.background(f)`, `F.count(f)` | Whether it must be drawn whole; the raw damage boxes; parts; surface; part count. |
| `F.ops(f)` | Every part's operations in order: the draw list of the same calls made on one scene. |
| `F.drawn(f, parts)` | The frame as a renderer leaves it: these parts, no damage, not whole. |
| `F.area(boxes, 0)`, `F.touched(boxes, box)` | Pixels in the boxes; whether a box meets any of them. |

Parts are matched by id in order: a part is normally found at once, and a
part moved, added or removed costs a scan of the parts left. The damage of a
changed part is its old and its new box; added and removed parts damage
their box; a reordered part damages what it overlaps.

A typical frame (Chromi's `examples/eco/grid.bend`):

```bend
def frame(m: Grid, last: F.Frame) -> F.Frame:
  b = F.begin(last, w, h, 1.0, background())
  b = F.part(b, button_id(), s => U.button(view, s, label))   # Kairo's id
  b = F.part(b, 2, s => paint_counter(s, counter))
  F.end(F.stamped(b, 3, 1, s => paint_cells(cells, s)))       # labels
```

The app keeps the frame `Gpu.render` answers and builds the next one from it.

## CPU reference (`replay.bend`)

| Function | Contract |
| --- | --- |
| `R.canvas(s)` | The scene painted into a fresh canvas at scale 1 with the canvas's blending. |
| `R.image(s)` | `C.finish` of that canvas: a `Base.Image` for the official window. |
| `R.pixels(s)` | Row-major `0xRRGGBBAA` words (`w * h` of them; the array may be larger): what the GPU path must reproduce. |
| `R.coverage(px, py, x0, y0, x1, y1, r, b)` | Coverage 0..255 of a pixel by a rounded box (`b` 0) or ring. |
| `R.frame_canvas(f)` | A retained frame painted whole (as `canvas` paints a scene). |
| `R.repaint(c, f)` | Paints only `f`'s damage over `c`, the picture of the frame `f` was built from: each damaged box is filled with the background, then every part meeting it is replayed within it, in order. Equals `frame_canvas(f)`; a frame that must be drawn whole is. |

Rounded coverage: 4x4 samples per pixel at 1/8, 3/8, 5/8 and 7/8 of the pixel
on each axis, in 1/8-pixel integers. A sample is inside a box with radius `r`
when it is within the box and, in a corner zone, within `r` of the corner's
center (`dx² + dy² <= r²`); a ring keeps the samples outside the box inset by
its border (radius `max(r - b, 0)`). `h` hits give `c = (255 h + 8) / 16`; the
color's alpha becomes `(alpha * c + 127) / 255`, then source-over as usual.
Voltra's shader applies the same rules (`Voltra/shaders/prim.frag`).

## GPU path (`gpu.bend`)

Requires [Voltra](https://github.com/amage-si/voltra) beside Chromi.

| Function | Contract |
| --- | --- |
| `Gpu.open(native, w, h, vsync)` | A renderer presenting into the native window Ankra hands over (`A.native(win)`), with a 1024x1024 atlas. |
| `Gpu.open_offscreen(w, h)` | A renderer drawing into an offscreen image (see `read`). |
| `Gpu.draw(r, s)` | `IO(Renderer)`. Uploads the bitmaps and masks the atlas has not seen (one transfer), then draws every operation as one Voltra quad in one draw call, clears to the scene's background and presents. A full atlas starts over with this frame's content. A failed scene ends the program with its error. |
| `Gpu.read(r)` | `IO(Renderer & Array<U32>)`: the last offscreen frame as `0xRRGGBBAA` words. |
| `Gpu.resize(r, w, h)`, `Gpu.pending(r)`, `Gpu.invalidate(r)`, `Gpu.target_size(r)`, `Gpu.close(r)` | Voltra's, through the renderer. |
| `Gpu.uploaded(r)`, `Gpu.entries(r)`, `Gpu.resets(r)` | Texels uploaded so far, atlas entries, atlas restarts. |
| `Gpu.plan(ops, atlas)` | The pure part of `draw`: quads, regions to upload, and whether something found no room. |
| `Gpu.render(r, f)` | `IO(Renderer & F.Frame)`. Draws a retained frame on Voltra's canvas and answers it as drawn (its parts with where their quads lie, no damage). Each damaged region is redrawn alone: the background, then the quads of every part that meets it, scissored to the region (Voltra's `paint`); the present names the regions. A part's quads are planned (atlas) when it is first drawn and written once into Voltra's store, which keeps them on the GPU; the part keeps where they lie while the atlas and the store last (its epoch), so a kept part costs no lookup, packing or copy, only a run of stored instances (adjacent parts' runs join into one draw); atlas content the frame needs is uploaded inside the frame. When a frame's new quads do not fit in the store, the store starts over (Voltra waits for the device) and the frame plans again every part it draws. Drawn whole when the frame asks for it, when the canvas does not hold the last picture, or when the damage covers more than half of the surface. A failed frame ends the program. A frame's planned parts belong to the renderer that drew it. |
| `Gpu.last_quads(r)`, `Gpu.last_partial(r)` | Quads uploaded and drawn by the last `render`, and whether it redrew only damage (0 and False after `draw`). |
