import Base
import ./color.bend as Color
import ./geometry.bend as G

# A frame as a draw list: the same validated drawing calls as the canvas
# (main.bend), recorded as physical operations instead of being painted.
# Logical geometry is resolved here, once, by the canvas's own rules
# (pixel-center coverage, clip intersection, floored bitmap origins), so
# every renderer of the list -- the CPU reference (replay.bend) or the GPU
# path (gpu.bend) -- draws exactly the same pixels.
#
# Operations, in drawing order (later on top):
#   Fill    an opaque-or-translucent box of whole pixels, already clipped;
#   Round   a box in 1/8 pixels with rounded corners (border 0) or its ring
#           (border > 0), antialiased by 4x4 samples per pixel (see
#           coverage in replay.bend), within a clip box;
#   Bitmap  a row-major RGBA8 image, one sample per pixel, within a clip;
#   Mask    a row-major coverage mask (0..255) of an ink color, within a
#           clip.
# Bitmaps and masks carry a key chosen by the caller: the same key must
# always mean the same pixels, so a GPU renderer can upload them once.
# An operation that cannot touch a pixel of its clip (outside the surface
# or the clip, or empty) is not recorded at all, so content far outside
# the window costs no planning, upload or drawing.
# Coordinates of Round, Bitmap and Mask are signed 32-bit values in U32
# bits; colors are straight RGBA8 0xRRGGBBAA in encoded sRGB.

type Op is Data:
  Fill{box: G.Box, color: U32}
  Round{x0: U32, y0: U32, x1: U32, y1: U32, radius: U32, border: U32, color: U32, clip: G.Box}
  Bitmap{key: U32, x: U32, y: U32, width: U32, height: U32, pixels: List<&2, U32>, clip: G.Box}
  Mask{key: U32, x: U32, y: U32, width: U32, height: U32, coverage: List<&2, U32>, ink: U32, clip: G.Box}

# A failed builder stays failed; `ops` exposes the first error.
type Scene is Data:
  Failed{message: String}
  Scene{width: U32, height: U32, scale: F32, background: U32, clip: G.Box,
    ops: List<&2, Op>}

def new.checked(valid: Bool, +width: U32, +height: U32, scale: F32, background: U32) -> Scene:
  match valid:
    case False{}:
      Failed{"Chromi: dimensions 1..4096, scale (0,16], opaque background required"}
    case True{}:
      Scene{width, height, scale, background, G.Box{0, 0, width, height}, Nil{}}

# A width x height surface (physical pixels) with a logical-to-physical
# scale and an opaque background, as `main.new`.
def new(+width: U32, +height: U32, +scale: F32, +background: U32) -> Scene:
  new.checked((width > 0 : U32) && (height > 0 : U32) &&
    (width <= 4096 : U32) && (height <= 4096 : U32) &&
    (scale > 0.0 : F32) && (scale <= 16.0 : F32) &&
    U32.is_eq(Color.alpha(background), 255), width, height, scale, background)

def reject(s: Scene, reason: String) -> Scene:
  match s:
    case Failed{message}:
      Failed{message}
    case Scene{w, h, sc, bg, clip, ops}:
      Failed{reason}

def push(s: Scene, op: Op) -> Scene:
  match s:
    case Failed{message}:
      Failed{message}
    case Scene{w, h, sc, bg, clip, ops}:
      Scene{w, h, sc, bg, clip, op <> ops}

def drawn(+box: G.Box, +color: U32) -> Bool:
  Bool.not(G.empty(box)) && U32.is_ne(Color.alpha(color), 0)

def fill.box(visible: Bool, s: Scene, +box: G.Box, +color: U32) -> Scene:
  match visible:
    case True{}:
      push(s, Fill{box, color})
    case False{}:
      s

def fill.valid(valid: Bool, s: Scene, rect: G.Rect, +color: U32) -> Scene:
  match valid s:
    case _ Failed{message}:
      Failed{message}
    case False{} _:
      Failed{"Chromi: rectangle must be finite with nonnegative width and height"}
    case True{} Scene{+w, +h, +sc, bg, +clip, ops}:
      +box = G.intersect(clip, G.physical(rect, sc, w, h))
      fill.box(drawn(box, color), Scene{w, h, sc, bg, clip, ops}, box, color)

def fill_rect(s: Scene, +rect: G.Rect, +color: U32) -> Scene:
  fill.valid(G.valid(rect), s, rect, color)

def clip.valid(valid: Bool, s: Scene, rect: G.Rect) -> Scene:
  match valid s:
    case _ Failed{message}:
      Failed{message}
    case False{} _:
      Failed{"Chromi: invalid clip rectangle"}
    case True{} Scene{+w, +h, +sc, bg, clip, ops}:
      Scene{w, h, sc, bg, G.intersect(clip, G.physical(rect, sc, w, h)), ops}

# Intersects the current clip, as `main.clip_rect`.
def clip_rect(s: Scene, +rect: G.Rect) -> Scene:
  clip.valid(G.valid(rect), s, rect)

def reset_clip(s: Scene) -> Scene:
  match s:
    case Failed{message}:
      Failed{message}
    case Scene{+w, +h, sc, bg, clip, ops}:
      Scene{w, h, sc, bg, G.Box{0, 0, w, h}, ops}

# An inward border of four boxes, without repeated corner composition, as
# `main.stroke_rect`.
def stroke.valid(valid: Bool, s: Scene, rect: G.Rect, +thickness: F32, +color: U32) -> Scene:
  match valid:
    case False{}:
      reject(s, "Chromi: invalid border geometry")
    case True{}:
      G.Rect{+x, +y, +w, +h} = rect
      +tx = F32.min(thickness, (w / 2.0 : F32))
      +ty = F32.min(thickness, (h / 2.0 : F32))
      a = fill_rect(s, G.Rect{x, y, w, ty}, color)
      b = fill_rect(a, G.Rect{x, (y + h - ty : F32), w, ty}, color)
      c = fill_rect(b, G.Rect{x, (y + ty : F32), tx, (h - 2.0 * ty : F32)}, color)
      fill_rect(c, G.Rect{(x + w - tx : F32), (y + ty : F32), tx, (h - 2.0 * ty : F32)}, color)

def stroke_rect(s: Scene, +rect: G.Rect, +thickness: F32, +color: U32) -> Scene:
  stroke.valid(G.valid(rect) && G.finite(thickness) && (thickness >= 0.0 : F32),
    s, rect, thickness, color)

# Rounded boxes
# -------------

# A finite F32 to signed 32-bit two's complement in U32 bits.
def to_i32(+v: F32) -> U32:
  Bool.pick(U32, (v < 0.0 : F32), (0 - F32.to_u32(F32.neg(v)) : U32), F32.to_u32(v))

# Logical units to the nearest 1/8 physical pixel.
def eighths(+v: F32, +scale: F32) -> U32:
  to_i32(F32.round((v * scale * 8.0 : F32)))

# The whole pixels a rounded box in 1/8 pixels can cover.
def round.pixels(+clip: G.Box, +x0: U32, +y0: U32, +x1: U32, +y1: U32) -> G.Box:
  +px = G.floor8(x0)
  +py = G.floor8(y0)
  G.cover(clip, px, py, (G.ceil8(x1) - px : U32), (G.ceil8(y1) - py : U32))

def round.keep(seen: Bool, op: Op, ops: List<&2, Op>) -> List<&2, Op>:
  match seen:
    case True{}:
      op <> ops
    case False{}:
      ops

def round.push(s: Scene, +x0: U32, +y0: U32, +x1: U32, +y1: U32, +r: U32, +b: U32, +color: U32) -> Scene:
  match s:
    case Failed{message}:
      Failed{message}
    case Scene{w, h, sc, bg, +clip, ops}:
      Scene{w, h, sc, bg, clip, round.keep(Bool.not(G.empty(round.pixels(clip, x0, y0, x1, y1))),
        Round{x0, y0, x1, y1, r, b, color, clip}, ops)}

def round.visible(visible: Bool, s: Scene, +x0: U32, +y0: U32, +x1: U32, +y1: U32,
  +r: U32, +b: U32, +color: U32) -> Scene:
  match visible:
    case True{}:
      round.push(s, x0, y0, x1, y1, r, b, color)
    case False{}:
      s

# Quantizes the box, clamps the radius to half the shorter side and the
# border to the same bound. A ring whose border rounds to nothing draws
# nothing (border 0 would mean a filled box).
def round.box(s: Scene, rect: G.Rect, +radius: F32, +ring: Bool, +width: F32, +color: U32,
  +scale: F32) -> Scene:
  G.Rect{+x, +y, +w, +h} = rect
  +x0 = eighths(x, scale)
  +y0 = eighths(y, scale)
  +x1 = eighths((x + w : F32), scale)
  +y1 = eighths((y + h : F32), scale)
  +half = (U32.min((x1 - x0 : U32), (y1 - y0 : U32)) / 2 : U32)
  +r = U32.min(eighths(radius, scale), half)
  +b = Bool.pick(U32, ring, U32.min(eighths(width, scale), half), 0)
  round.visible(U32.is_ne(x1, x0) && U32.is_ne(y1, y0) && U32.is_ne(Color.alpha(color), 0) &&
    Bool.not(ring && U32.is_eq(b, 0)), s, x0, y0, x1, y1, r, b, color)

def scale_of(s: Scene) -> F32:
  match s:
    case Failed{message}:
      1.0
    case Scene{w, h, sc, bg, clip, ops}:
      sc

def round.valid(valid: Bool, +s: Scene, rect: G.Rect, +radius: F32, +ring: Bool, +width: F32,
  +color: U32) -> Scene:
  match valid:
    case False{}:
      reject(s, "Chromi: invalid rounded rectangle")
    case True{}:
      round.box(s, rect, radius, ring, width, color, scale_of(s))

# A filled rectangle with corners rounded by `radius` (logical units),
# antialiased: each pixel's coverage counts 4x4 samples.
def round_rect(s: Scene, +rect: G.Rect, +radius: F32, +color: U32) -> Scene:
  round.valid(G.valid(rect) && G.finite(radius) && (radius >= 0.0 : F32), s, rect, radius,
    False{}, 0.0, color)

# The border of such a rectangle, `width` logical units wide inward; the
# inner corners are rounded by max(radius - width, 0).
def border(s: Scene, +rect: G.Rect, +radius: F32, +width: F32, +color: U32) -> Scene:
  round.valid(G.valid(rect) && G.finite(radius) && (radius >= 0.0 : F32) && G.finite(width) &&
    (width >= 0.0 : F32), s, rect, radius, True{}, width, color)

# Bitmaps and masks
# -----------------

def data_valid(data: List<&2, U32>, expected: Nat, +mask: Bool) -> Bool:
  match data expected:
    case Nil{} 0n:
      True{}
    case value <> rest 1n+n:
      (Bool.not(mask) || (value <= 255 : U32)) && data_valid(rest, n, mask)
    case _ _:
      False{}

def image.op(mask: Bool, +key: U32, +x: U32, +y: U32, +width: U32, +height: U32,
  data: List<&2, U32>, +ink: U32, +clip: G.Box) -> Op:
  match mask:
    case True{}:
      Mask{key, x, y, width, height, data, ink, clip}
    case False{}:
      Bitmap{key, x, y, width, height, data, clip}

def image.keep(empty: Bool, op: Op, ops: List<&2, Op>) -> List<&2, Op>:
  match empty:
    case True{}:
      ops
    case False{}:
      op <> ops

def image.push(valid: Bool, s: Scene, +key: U32, +x: F32, +y: F32, +width: U32, +height: U32,
  data: List<&2, U32>, +mask: Bool, +ink: U32) -> Scene:
  match valid s:
    case _ Failed{message}:
      Failed{message}
    case False{} _:
      Failed{"Chromi: invalid bitmap dimensions, data length, origin or coverage"}
    case True{} Scene{w, h, +sc, bg, +clip, ops}:
      +px = to_i32(F32.floor((x * sc : F32)))
      +py = to_i32(F32.floor((y * sc : F32)))
      Scene{w, h, sc, bg, clip, image.keep(Bool.not(G.meets(clip, px, py, width, height)),
        image.op(mask, key, px, py, width, height, data, ink, clip), ops)}

def image.bounds(valid: Bool, s: Scene, +key: U32, +x: F32, +y: F32, +width: U32, +height: U32,
  +data: List<&2, U32>, +mask: Bool, +ink: U32) -> Scene:
  match valid:
    case False{}:
      reject(s, "Chromi: bitmap dimensions or origin out of range")
    case True{}:
      image.push(data_valid(data, U32.to_nat((width * height : U32)), mask), s, key, x, y,
        width, height, data, mask, ink)

# Validated pixels
# ----------------

# Bitmap or mask data checked once, when it is made, so drawing it in every
# frame costs no validation pass over its samples (a 256x256 image is
# 65,536 of them).
type Pixels is Data:
  Pixels{key: U32, width: U32, height: U32, data: List<&2, U32>, mask: Bool}

def pixels.checked(ok: Bool, +key: U32, +width: U32, +height: U32, data: List<&2, U32>,
  +mask: Bool) -> Result<&2, &2, String, Pixels>:
  match ok:
    case False{}:
      Fail{"Chromi: invalid bitmap dimensions, data length or coverage"}
    case True{}:
      Done{Pixels{key, width, height, data, mask}}

def pixels.made(+key: U32, +width: U32, +height: U32, +data: List<&2, U32>, +mask: Bool) ->
  Result<&2, &2, String, Pixels>:
  pixels.checked((width <= 4096 : U32) && (height <= 4096 : U32) &&
    data_valid(data, U32.to_nat((width * height : U32)), mask), key, width, height, data, mask)

# A row-major RGBA8 bitmap (exactly width * height words), validated once.
def rgba(+key: U32, +width: U32, +height: U32, +data: List<&2, U32>) -> Result<&2, &2, String, Pixels>:
  pixels.made(key, width, height, data, False{})

# A row-major coverage mask (0..255, exactly width * height values),
# validated once.
def coverage(+key: U32, +width: U32, +height: U32, +data: List<&2, U32>) -> Result<&2, &2, String, Pixels>:
  pixels.made(key, width, height, data, True{})

def draw.valid(valid: Bool, s: Scene, p: Pixels, +x: F32, +y: F32, +ink: U32) -> Scene:
  match valid:
    case False{}:
      reject(s, "Chromi: bitmap origin out of range")
    case True{}:
      Pixels{+key, +w, +h, data, +mask} = p
      image.push(True{}, s, key, x, y, w, h, data, mask, ink)

# Validated pixels at a logical origin, floored to a physical pixel, one
# sample per pixel; a mask is drawn in `ink` (ignored for bitmaps).
def draw(s: Scene, p: Pixels, +x: F32, +y: F32, +ink: U32) -> Scene:
  draw.valid(G.finite(x) && G.finite(y), s, p, x, y, ink)

# A row-major RGBA8 bitmap (exactly width * height words) at a logical
# origin, floored to a physical pixel; one sample per pixel, as
# `main.blit_rgba`. `key` names these pixels for the GPU path.
def blit_rgba(s: Scene, +key: U32, +x: F32, +y: F32, +width: U32, +height: U32,
  data: List<&2, U32>) -> Scene:
  image.bounds((width <= 4096 : U32) && (height <= 4096 : U32) && G.finite(x) && G.finite(y),
    s, key, x, y, width, height, data, False{}, 0)

# A row-major coverage mask (0..255) of `ink`, as `main.blit_mask`.
def blit_mask(s: Scene, +key: U32, +x: F32, +y: F32, +width: U32, +height: U32,
  coverage: List<&2, U32>, +ink: U32) -> Scene:
  image.bounds((width <= 4096 : U32) && (height <= 4096 : U32) && G.finite(x) && G.finite(y),
    s, key, x, y, width, height, coverage, True{}, ink)

# Results
# -------

# The operations in drawing order, or the first error.
def ops(s: Scene) -> Result<&1, &1, U32 & String, List<&2, Op>>:
  match s:
    case Failed{message}:
      Fail{(22, message)}
    case Scene{w, h, sc, bg, clip, ops}:
      Done{List.reverse(&2, Op, ops)}

def size(s: Scene) -> U32 & U32:
  match s:
    case Failed{message}:
      (0, 0)
    case Scene{w, h, sc, bg, clip, ops}:
      (w, h)

def background(s: Scene) -> U32:
  match s:
    case Failed{message}:
      0
    case Scene{w, h, sc, bg, clip, ops}:
      bg

def count(s: Scene) -> U32:
  match s:
    case Failed{message}:
      0
    case Scene{w, h, sc, bg, clip, ops}:
      U32.from_nat(List.length(&2, Op, ops))

# Parts of retained frames
# ------------------------
# (frame.bend keeps parts of a frame from one frame to the next.)

def visible.of(valid: Bool, +clip: G.Box, rect: G.Rect, +sc: F32) -> Bool:
  match valid:
    case False{}:
      True{}
    case True{}:
      G.Rect{+x, +y, +w, +h} = rect
      +x0 = to_i32(F32.floor((x * sc : F32)))
      +y0 = to_i32(F32.floor((y * sc : F32)))
      G.meets(clip, x0, y0, (to_i32(F32.ceil(((x + w) * sc : F32))) - x0 : U32),
        (to_i32(F32.ceil(((y + h) * sc : F32))) - y0 : U32))

# Whether anything drawn within `rect` (logical units) could show: the
# whole pixels it covers meet the current clip. For skipping work whose
# operations would be culled anyway (laying out or painting text far
# outside the window); an invalid rectangle answers True.
def visible(s: Scene, +rect: G.Rect) -> Bool:
  match s:
    case Failed{message}:
      False{}
    case Scene{w, h, +sc, bg, +clip, ops}:
      visible.of(G.valid(rect), clip, rect, sc)

def same_box(a: G.Box, b: G.Box) -> Bool:
  G.Box{ax, ay, ar, ab} = a
  G.Box{bx, by, br, bb} = b
  U32.is_eq(ax, bx) && U32.is_eq(ay, by) && U32.is_eq(ar, br) && U32.is_eq(ab, bb)

# Whether two operations draw the same pixels. Bitmaps and masks compare
# by key (the same key always means the same pixels), not sample by sample.
def same_op(a: Op, b: Op) -> Bool:
  match a b:
    case Fill{ab, ac} Fill{bb, bc}:
      same_box(ab, bb) && U32.is_eq(ac, bc)
    case Round{ax0, ay0, ax1, ay1, ar, abd, ac, aclip} Round{bx0, by0, bx1, by1, br, bbd, bc, bclip}:
      U32.is_eq(ax0, bx0) && U32.is_eq(ay0, by0) && U32.is_eq(ax1, bx1) && U32.is_eq(ay1, by1) &&
        U32.is_eq(ar, br) && U32.is_eq(abd, bbd) && U32.is_eq(ac, bc) && same_box(aclip, bclip)
    case Bitmap{ak, ax, ay, aw, ah, ad, aclip} Bitmap{bk, bx, by, bw, bh, bd, bclip}:
      U32.is_eq(ak, bk) && U32.is_eq(ax, bx) && U32.is_eq(ay, by) && U32.is_eq(aw, bw) &&
        U32.is_eq(ah, bh) && same_box(aclip, bclip)
    case Mask{ak, ax, ay, aw, ah, ad, ai, aclip} Mask{bk, bx, by, bw, bh, bd, bi, bclip}:
      U32.is_eq(ak, bk) && U32.is_eq(ax, bx) && U32.is_eq(ay, by) && U32.is_eq(aw, bw) &&
        U32.is_eq(ah, bh) && U32.is_eq(ai, bi) && same_box(aclip, bclip)
    case _ _:
      False{}

def same_ops(a: List<&2, Op>, b: List<&2, Op>) -> Bool:
  match a b:
    case Nil{} Nil{}:
      True{}
    case Con{x, xs} Con{y, ys}:
      same_op(x, y) && same_ops(xs, ys)
    case _ _:
      False{}

# The surface pixels an operation can touch.
def op_box(o: Op) -> G.Box:
  match o:
    case Fill{box, color}:
      box
    case Round{x0, y0, x1, y1, r, b, color, clip}:
      round.pixels(clip, x0, y0, x1, y1)
    case Bitmap{key, x, y, w, h, data, clip}:
      G.cover(clip, x, y, w, h)
    case Mask{key, x, y, w, h, data, ink, clip}:
      G.cover(clip, x, y, w, h)

# The box holding every pixel the operations can touch, joined to `acc`.
def bounds(os: List<&2, Op>, +acc: G.Box) -> G.Box:
  match os:
    case Nil{}:
      acc
    case Con{o, rest}:
      bounds(rest, G.union(acc, op_box(o)))
