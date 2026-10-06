# Chromi API

The core renderer imports only `Base` and modules in this repository. The
`Canvas` builder is affine. Operations consume a canvas and return the next
canvas; a failure preserves the first error through subsequent operations.

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
