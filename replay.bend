import Base
import ./main.bend as C
import ./geometry.bend as G
import ./color.bend as Color
import ./scene.bend as S

# The CPU reference renderer of a draw list (scene.bend): every operation
# is painted into Chromi's quadtree canvas with the canvas's own blending
# (Color.over, integer rounding in encoded sRGB). The GPU path (gpu.bend)
# must produce the same bytes; tests compare the two pixel by pixel.
#
# Rounded boxes follow the coverage rule shared with Voltra's shader
# (Voltra/shaders/prim.frag): 4x4 samples per pixel at 1/8, 3/8, 5/8 and
# 7/8 of the pixel on each axis, in 1/8-pixel integer coordinates; a
# sample is inside a box (x0, y0)-(x1, y1) with corner radius r when it is
# within the box and, in a corner zone, within r of the corner's center;
# a ring keeps the samples outside the box inset by its border (radius
# max(r - border, 0)). h hits give coverage c = (255 h + 8) / 16, and the
# color's alpha becomes (alpha * c + 127) / 255, as for coverage masks.

# Signed 32-bit comparisons on two's complement words.
def slt(+a: U32, +b: U32) -> Bool:
  U32.is_lt((a .^. 2147483648 : U32), (b .^. 2147483648 : U32))

def smax(+a: U32, +b: U32) -> U32:
  Bool.pick(U32, slt(a, b), b, a)

def smin(+a: U32, +b: U32) -> U32:
  Bool.pick(U32, slt(a, b), a, b)

def floor8(+v: U32) -> U32:
  Bool.pick(U32, slt(v, 0), (0 - (((0 - v : U32) + 7 : U32) / 8 : U32) : U32), (v / 8 : U32))

def ceil8(+v: U32) -> U32:
  (0 - floor8((0 - v : U32)) : U32)

# Coverage
# --------

def corner(+s: U32, +lo: U32, +hi: U32, +r: U32) -> U32:
  Bool.pick(U32, slt(s, (lo + r : U32)), (lo + r - s : U32),
    Bool.pick(U32, slt(s, (hi - r : U32)), 0, (s - (hi - r) : U32)))

def inside(+sx: U32, +sy: U32, +x0: U32, +y0: U32, +x1: U32, +y1: U32, +r: U32) -> Bool:
  +dx = corner(sx, x0, x1, r)
  +dy = corner(sy, y0, y1, r)
  Bool.not(slt(sx, x0)) && Bool.not(slt(sy, y0)) && slt(sx, x1) && slt(sy, y1) &&
    (U32.is_eq(dx, 0) || U32.is_eq(dy, 0) || U32.is_le((dx * dx + dy * dy : U32), (r * r : U32)))

def hit(+sx: U32, +sy: U32, +x0: U32, +y0: U32, +x1: U32, +y1: U32, +r: U32, +b: U32) -> U32:
  +ix0 = (x0 + b : U32)
  +iy0 = (y0 + b : U32)
  +ix1 = (x1 - b : U32)
  +iy1 = (y1 - b : U32)
  +ring = U32.is_eq(b, 0) || Bool.not(slt(ix0, ix1)) || Bool.not(slt(iy0, iy1)) ||
    Bool.not(inside(sx, sy, ix0, iy0, ix1, iy1, (r - U32.min(r, b) : U32)))
  Bool.to_u32(inside(sx, sy, x0, y0, x1, y1, r) && ring)

def hits(n: Nat, +k: U32, +px: U32, +py: U32, +x0: U32, +y0: U32, +x1: U32, +y1: U32,
  +r: U32, +b: U32, +acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+p:
      +sx = (px * 8 + 1 + 2 * (k % 4) : U32)
      +sy = (py * 8 + 1 + 2 * (k / 4) : U32)
      hits(p, (k + 1 : U32), px, py, x0, y0, x1, y1, r, b, (acc + hit(sx, sy, x0, y0, x1, y1, r, b) : U32))

# Coverage (0..255) of pixel (px, py) by a rounded box or ring.
def coverage(+px: U32, +py: U32, +x0: U32, +y0: U32, +x1: U32, +y1: U32, +r: U32, +b: U32) -> U32:
  ((255 * hits(16n, 0, px, py, x0, y0, x1, y1, r, b, 0) + 8) / 16 : U32)

# Painting
# --------

def with_clip(c: C.Canvas, +box: G.Box) -> C.Canvas:
  match c:
    case C.Failed{m}:
      C.Failed{m}
    case C.Canvas{w, h, sc, d, s, clip, px}:
      C.Canvas{w, h, sc, d, s, box, px}

def full(c: C.Canvas) -> C.Canvas:
  match c:
    case C.Failed{m}:
      C.Failed{m}
    case C.Canvas{+w, +h, sc, d, s, clip, px}:
      C.Canvas{w, h, sc, d, s, G.Box{0, 0, w, h}, px}

# One pixel, through the canvas's clip.
def dot(c: C.Canvas, +x: U32, +y: U32, +color: U32) -> C.Canvas:
  C.physical(c, G.Box{x, y, (x + 1 : U32), (y + 1 : U32)}, color)

def onscreen(+x: U32, +y: U32) -> Bool:
  Bool.not(slt(x, 0)) && Bool.not(slt(y, 0))

def sample.color(mask: Bool, +value: U32, +ink: U32) -> U32:
  match mask:
    case True{}:
      Color.coverage(ink, value)
    case False{}:
      value

def sample.paint(visible: Bool, c: C.Canvas, +x: U32, +y: U32, +color: U32) -> C.Canvas:
  match visible:
    case True{}:
      dot(c, x, y, color)
    case False{}:
      c

# A bitmap or mask, one sample per pixel, row-major from (x, y).
def samples(data: List<&2, U32>, c: C.Canvas, +x: U32, +y: U32, +w: U32, +i: U32,
  +mask: Bool, +ink: U32) -> C.Canvas:
  match data:
    case Nil{}:
      c
    case v <> rest:
      +px = (x + i % w : U32)
      +py = (y + i / w : U32)
      samples(rest, sample.paint(onscreen(px, py), c, px, py, sample.color(mask, v, ink)),
        x, y, w, (i + 1 : U32), mask, ink)

def flush.pick(empty: Bool, c: C.Canvas, +start: U32, +x: U32, +y: U32, +cov: U32, +color: U32) -> C.Canvas:
  match empty:
    case True{}:
      c
    case False{}:
      C.physical(c, G.Box{start, y, x, (y + 1 : U32)}, Color.coverage(color, cov))

# A run of pixels [start, x) of row y at one coverage.
def flush(c: C.Canvas, +start: U32, +x: U32, +y: U32, +cov: U32, +color: U32) -> C.Canvas:
  flush.pick(U32.is_eq(cov, 0), c, start, x, y, cov, color)

type Shape is Data:
  Shape{x0: U32, y0: U32, x1: U32, y1: U32, r: U32, b: U32, color: U32}

def run.next(same: Bool, c: C.Canvas, +start: U32, +x: U32, +y: U32, +cur: U32, +color: U32) -> C.Canvas:
  match same:
    case True{}:
      c
    case False{}:
      flush(c, start, x, y, cur, color)

def shape_color(sh: Shape) -> U32:
  Shape{x0, y0, x1, y1, r, b, color} = sh
  color

def shape_coverage(sh: Shape, +x: U32, +y: U32) -> U32:
  Shape{+x0, +y0, +x1, +y1, +r, +b, color} = sh
  coverage(x, y, x0, y0, x1, y1, r, b)

# Pixels of row y from x to x + n, grouped into runs of equal coverage.
def row(n: Nat, c: C.Canvas, +x: U32, +y: U32, +start: U32, +cur: U32, +sh: Shape) -> C.Canvas:
  match n:
    case 0n:
      flush(c, start, x, y, cur, shape_color(sh))
    case 1n+p:
      +cov = shape_coverage(sh, x, y)
      +same = U32.is_eq(cov, cur)
      row(p, run.next(same, c, start, x, y, cur, shape_color(sh)), (x + 1 : U32), y,
        Bool.pick(U32, same, start, x), cov, sh)

def rows(n: Nat, c: C.Canvas, +y: U32, +left: U32, +cols: Nat, +sh: Shape) -> C.Canvas:
  match n:
    case 0n:
      c
    case 1n+p:
      rows(p, row(cols, c, left, y, left, 0, sh), (y + 1 : U32), left, cols, sh)

def span(+lo: U32, +hi: U32) -> Nat:
  Bool.pick(Nat, slt(lo, hi), U32.to_nat((hi - lo : U32)), 0n)

# A rounded box or ring, row by row, within its clip box.
def round(c: C.Canvas, +x0: U32, +y0: U32, +x1: U32, +y1: U32, +r: U32, +b: U32,
  +color: U32, clip: G.Box) -> C.Canvas:
  G.Box{+cx0, +cy0, +cx1, +cy1} = clip
  +left = smax(floor8(x0), cx0)
  +right = smin(ceil8(x1), cx1)
  +top = smax(floor8(y0), cy0)
  +bottom = smin(ceil8(y1), cy1)
  rows(span(top, bottom), c, top, left, span(left, right), Shape{x0, y0, x1, y1, r, b, color})

def op(c: C.Canvas, o: S.Op) -> C.Canvas:
  match o:
    case S.Fill{box, color}:
      C.physical(full(c), box, color)
    case S.Round{x0, y0, x1, y1, r, b, color, clip}:
      round(full(c), x0, y0, x1, y1, r, b, color, clip)
    case S.Bitmap{key, x, y, w, h, data, clip}:
      samples(data, with_clip(c, clip), x, y, w, 0, False{}, 0)
    case S.Mask{key, x, y, w, h, data, ink, clip}:
      samples(data, with_clip(c, clip), x, y, w, 0, True{}, ink)

def ops(os: List<&2, S.Op>, c: C.Canvas) -> C.Canvas:
  match os:
    case Nil{}:
      c
    case o <> rest:
      ops(rest, op(c, o))

def canvas.from(r: Result<&1, &1, U32 & String, List<&2, S.Op>>, +w: U32, +h: U32, +bg: U32) -> C.Canvas:
  match r:
    case Fail{(code, message)}:
      C.Failed{message}
    case Done{os}:
      full(ops(os, C.new(w, h, 1.0, bg)))

def canvas.sized(+s: S.Scene, size: U32 & U32) -> C.Canvas:
  (w, h) = size
  canvas.from(S.ops(s), w, h, S.background(s))

# The scene painted on the CPU into a canvas (physical pixels, scale 1).
def canvas(+s: S.Scene) -> C.Canvas:
  canvas.sized(s, S.size(s))

# The scene as Base.Image, for the official runtime window.
def image(+s: S.Scene) -> Result<&1, &1, U32 & String, Image>:
  C.finish(canvas(s))

# Flat pixels
# -----------

def fill_cols(n: Nat, a: Array<U32>, +i: U32, +c: U32) -> Array<U32>:
  match n:
    case 0n:
      a
    case 1n+p:
      fill_cols(p, Array.set(U32, a, i, c), (i + 1 : U32), c)

def fill_rows(n: Nat, a: Array<U32>, +i: U32, +stride: U32, +cols: Nat, +c: U32) -> Array<U32>:
  match n:
    case 0n:
      a
    case 1n+p:
      fill_rows(p, fill_cols(cols, a, i, c), (i + stride : U32), stride, cols, c)

def clipped(+pos: U32, +side: U32, +limit: U32) -> U32:
  Bool.pick(U32, U32.is_ge(pos, limit), 0, (U32.min((pos + side : U32), limit) - pos : U32))

# A quadtree of RGBA leaves as a row-major w x h array.
def flatten(img: Image, a: Array<U32>, +x: U32, +y: U32, +side: U32, +w: U32, +h: U32) -> Array<U32>:
  match img:
    case Pix{rgba}:
      fill_rows(U32.to_nat(clipped(y, side, h)), a, (y * w + x : U32), w,
        U32.to_nat(clipped(x, side, w)), rgba)
    case Qua{q0, q1, q2, q3}:
      +half = (side / 2 : U32)
      +right = (x + half : U32)
      +bottom = (y + half : U32)
      flatten(q3, flatten(q2, flatten(q1, flatten(q0, a, x, y, half, w, h),
        right, y, half, w, h), x, bottom, half, w, h), right, bottom, half, w, h)

def depth.of(+n: U32) -> Nat:
  Bool.pick(Nat, U32.is_le(n, 1), 0n, 1n+U32.log2((n - 1 : U32)))

def pixels.of(c: C.Canvas) -> Result<&1, &1, U32 & String, Array<U32>>:
  match c:
    case C.Failed{message}:
      Fail{(22, message)}
    case C.Canvas{+w, +h, sc, d, +side, clip, px}:
      Done{flatten(px, Array.new(U32, depth.of((w * h : U32)), 0), 0, 0, side, w, h)}

# The scene painted on the CPU, as row-major 0xRRGGBBAA words (w x h of
# them; the array may be larger): what the GPU path must reproduce.
def pixels(+s: S.Scene) -> Result<&1, &1, U32 & String, Array<U32>>:
  pixels.of(canvas(s))
