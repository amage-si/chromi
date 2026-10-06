import Base
import ./main.bend as C
import ./geometry.bend as G
import ./color.bend as Color
import ./scene.bend as S
import ./replay.bend as R

def check(ok: Bool, name: String) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("PASS " ++ name)
    case False{}:
      IO.die(Unit, 1, "FAIL " ++ name)

def equals(value: Maybe<U32>, wanted: U32) -> Bool:
  match value:
    case None{}:
      False{}
    case Some{got}:
      U32.is_eq(got, wanted)

def absent(value: Maybe<U32>) -> Bool:
  match value:
    case None{}:
      True{}
    case Some{x}:
      False{}

def failed(canvas: C.Canvas) -> Bool:
  Result.is_fail(&1, &1, U32 & String, Image, C.finish(canvas))

def base() -> C.Canvas:
  C.new(8, 6, 1.0, 255)

def rectangle() -> C.Canvas:
  C.fill_rect(base(), G.Rect{F32.neg(2.0), 1.0, 5.0, 2.0}, 4278190335)

def clip() -> C.Canvas:
  C.fill_rect(C.clip_rect(base(), G.Rect{2.0, 2.0, 2.0, 2.0}),
    G.Rect{0.0, 0.0, 8.0, 6.0}, 16711935)

def mask() -> C.Canvas:
  C.blit_mask(base(), 1.0, 1.0, 3, 1, [0, 128, 255], 4294967295)

def quadrants() -> C.Canvas:
  c = C.fill_rect(base(), G.Rect{4.0, 0.0, 4.0, 4.0}, 4278190335)
  c = C.fill_rect(c, G.Rect{0.0, 4.0, 4.0, 2.0}, 16711935)
  C.fill_rect(c, G.Rect{4.0, 4.0, 4.0, 2.0}, 65535)

def first_error(canvas: C.Canvas) -> Bool:
  match canvas:
    case C.Failed{"first"}: True{}
    case _: False{}

def output_leaf(result: Result<&1, &1, U32 & String, Image>, wanted: U32) -> Bool:
  match result:
    case Done{Pix{color}}:
      U32.is_eq(color, wanted)
    case _:
      False{}

def output_quadrants(result: Result<&1, &1, U32 & String, Image>) -> Bool:
  match result:
    case Done{Qua{Pix{16711680}, Pix{65280}, Pix{255}, Pix{16777215}}}:
      True{}
    case _:
      False{}

def four_colors() -> C.Canvas:
  c = C.new(2, 2, 1.0, 4278190335)
  c = C.fill_rect(c, G.Rect{1.0, 0.0, 1.0, 1.0}, 16711935)
  c = C.fill_rect(c, G.Rect{0.0, 1.0, 1.0, 1.0}, 65535)
  C.fill_rect(c, G.Rect{1.0, 1.0, 1.0, 1.0}, 4294967295)

# Draw lists
# ----------

def ramp.go(n: Nat, +i: U32) -> List<&2, U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      ((i * 37) % 256 : U32) <> ramp.go(p, (i + 1 : U32))

def ramp(+n: U32) -> List<&2, U32>:
  ramp.go(U32.to_nat(n), 0)

def rgba.go(n: Nat, +i: U32) -> List<&2, U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      ((((i * 37) % 256 : U32) * 16843009) .^. 2864434397 : U32) <> rgba.go(p, (i + 1 : U32))

def rgba(+n: U32) -> List<&2, U32>:
  rgba.go(U32.to_nat(n), 0)

# The same calls on the canvas and in a scene.
def drawn.canvas() -> C.Canvas:
  c = C.new(40, 30, 2.0, 336860415)
  c = C.fill_rect(c, G.Rect{1.5, 2.25, 10.0, 6.0}, 2164195456)
  c = C.stroke_rect(c, G.Rect{2.0, 1.0, 15.0, 12.0}, 1.0, 4294967295)
  c = C.clip_rect(c, G.Rect{3.0, 3.0, 9.0, 8.0})
  c = C.blit_mask(c, 2.5, 2.5, 7, 5, ramp(35), 4286595200)
  c = C.blit_rgba(c, 6.0, 4.0, 5, 6, rgba(30))
  c = C.reset_clip(c)
  C.fill_rect(c, G.Rect{F32.neg(2.0), 10.0, 6.0, 9.0}, 16744447)

def drawn.scene() -> S.Scene:
  s = S.new(40, 30, 2.0, 336860415)
  s = S.fill_rect(s, G.Rect{1.5, 2.25, 10.0, 6.0}, 2164195456)
  s = S.stroke_rect(s, G.Rect{2.0, 1.0, 15.0, 12.0}, 1.0, 4294967295)
  s = S.clip_rect(s, G.Rect{3.0, 3.0, 9.0, 8.0})
  s = S.blit_mask(s, 1, 2.5, 2.5, 7, 5, ramp(35), 4286595200)
  s = S.blit_rgba(s, 2, 6.0, 4.0, 5, 6, rgba(30))
  s = S.reset_clip(s)
  S.fill_rect(s, G.Rect{F32.neg(2.0), 10.0, 6.0, 9.0}, 16744447)

def same_arrays(n: Nat, a: Array<U32> & U32, b: Array<U32> & U32, +i: U32) -> Bool:
  match n:
    case 0n:
      True{}
    case 1n+p:
      (xa, +va) = a
      (xb, +vb) = b
      +j = (i + 1 : U32)
      U32.is_eq(va, vb) && same_arrays(p, Array.get(U32, xa, j), Array.get(U32, xb, j), j)

def same_result(a: Result<&1, &1, U32 & String, Array<U32>>, b: Result<&1, &1, U32 & String, Array<U32>>) -> Bool:
  match a b:
    case Done{x} Done{y}:
      same_arrays(1200n, Array.get(U32, x, 0), Array.get(U32, y, 0), 0)
    case _ _:
      False{}

def via_pixels(r: Result<&2, &2, String, S.Pixels>, q: Result<&2, &2, String, S.Pixels>) -> S.Scene:
  match r q:
    case Done{m} Done{b}:
      s = S.new(40, 30, 2.0, 336860415)
      s = S.fill_rect(s, G.Rect{1.5, 2.25, 10.0, 6.0}, 2164195456)
      s = S.stroke_rect(s, G.Rect{2.0, 1.0, 15.0, 12.0}, 1.0, 4294967295)
      s = S.clip_rect(s, G.Rect{3.0, 3.0, 9.0, 8.0})
      s = S.draw(s, m, 2.5, 2.5, 4286595200)
      s = S.draw(s, b, 6.0, 4.0, 0)
      s = S.reset_clip(s)
      S.fill_rect(s, G.Rect{F32.neg(2.0), 10.0, 6.0, 9.0}, 16744447)
    case _ _:
      S.Failed{"pixels rejected"}

def pixels_failed(r: Result<&2, &2, String, S.Pixels>) -> Bool:
  match r:
    case Fail{e}: True{}
    case Done{p}: False{}

def scene_failed(s: S.Scene) -> Bool:
  Result.is_fail(&1, &1, U32 & String, List<&2, S.Op>, S.ops(s))

def first_op.of(r: Result<&1, &1, U32 & String, List<&2, S.Op>>) -> List<&2, U32>:
  match r:
    case Done{Con{S.Round{x0, y0, x1, y1, r, b, c, clip}, rest}}:
      [x0, y0, x1, y1, r, b]
    case Done{Con{S.Fill{G.Box{x0, y0, x1, y1}, c}, rest}}:
      [x0, y0, x1, y1]
    case _:
      []

def first_op(s: S.Scene) -> List<&2, U32>:
  first_op.of(S.ops(s))

def same_words(xs: List<&2, U32>, ys: List<&2, U32>) -> Bool:
  match xs ys:
    case Nil{} Nil{}: True{}
    case Con{a, ra} Con{b, rb}: U32.is_eq(a, b) && same_words(ra, rb)
    case _ _: False{}

def main() -> IO(Unit):
  do IO<Unit>:
    check(equals(C.pixel(C.new(1, 1, 1.0, 4278190335), 0, 0), 4278190335), "1x1 and RGBA order")
    check(failed(C.new(0, 4, 1.0, 255)), "zero surface rejected")
    check(failed(C.new(4097, 4, 1.0, 255)), "surface bound")
    check(failed(C.new(8, 4, 0.0, 255)), "zero scale rejected")
    check(failed(C.new(8, 4, 17.0, 255)), "scale bound")
    check(failed(C.new(8, 4, 1.0, 0)), "transparent background rejected")
    check(failed(C.fill_rect(base(), G.Rect{0.0, 0.0, F32.neg(1.0), 2.0}, 255)), "negative rectangle rejected")
    check(failed(C.fill_rect(base(), G.Rect{2000000.0, 0.0, 1.0, 2.0}, 255)), "coordinate bound")
    check(equals(C.pixel(rectangle(), 0, 1), 4278190335), "negative x clips")
    check(equals(C.pixel(rectangle(), 2, 2), 4278190335), "rectangle last interior pixel")
    check(equals(C.pixel(rectangle(), 3, 2), 255), "exclusive right")
    check(equals(C.pixel(rectangle(), 2, 3), 255), "exclusive bottom")
    check(equals(C.pixel(C.fill_rect(base(), G.Rect{1.0, 1.0, 0.0, 2.0}, 4294967295), 1, 1), 255), "zero width draws nothing")
    check(equals(C.pixel(C.fill_rect(base(), G.Rect{0.5, 0.5, 1.0, 1.0}, 4294967295), 0, 0), 4294967295), "pixel centre coverage")
    check(equals(C.pixel(C.fill_rect(base(), G.Rect{0.5, 0.5, 1.0, 1.0}, 4294967295), 1, 0), 255), "fractional exclusive edge")
    check(equals(C.pixel(C.fill_rect(C.new(8, 8, 2.0, 255), G.Rect{1.0, 1.0, 1.0, 1.0}, 4294967295), 3, 3), 4294967295), "explicit logical scale")
    check(equals(C.pixel(clip(), 2, 2), 16711935), "clip inside")
    check(equals(C.pixel(clip(), 1, 2), 255), "clip outside")
    check(equals(C.pixel(C.fill_rect(C.reset_clip(clip()), G.Rect{0.0, 0.0, 1.0, 1.0}, 65535), 0, 0), 65535), "clip reset")
    check(equals(C.pixel(mask(), 1, 1), 255), "zero mask coverage")
    check(equals(C.pixel(mask(), 2, 1), 2155905279), "half mask coverage")
    check(equals(C.pixel(mask(), 3, 1), 4294967295), "full mask coverage")
    check(failed(C.blit_mask(base(), 0.0, 0.0, 1, 1, [256], 4294967295)), "invalid coverage rejected")
    check(failed(C.blit_mask(base(), 0.0, 0.0, 2, 1, [255], 4294967295)), "short mask rejected")
    check(failed(C.blit_mask(base(), 0.0, 0.0, 1, 1, [255, 255], 4294967295)), "long mask rejected")
    check(equals(C.pixel(C.blit_mask(base(), 0.0, 0.0, 0, 0, Nil{}, 4294967295), 0, 0), 255), "empty space glyph accepted")
    check(equals(C.pixel(C.blit_rgba(base(), F32.neg(1.0), 0.0, 2, 1, [4278190335, 65535]), 0, 0), 65535), "bitmap clipping preserves source index")
    check(U32.is_eq(Color.over(4278190208, 255), 2147483903), "half red over black")
    check(equals(C.pixel(C.stroke_rect(base(), G.Rect{1.0, 1.0, 4.0, 4.0}, 1.0, 4294967295), 2, 2), 255), "border leaves interior")
    check(equals(C.pixel(C.stroke_rect(base(), G.Rect{1.0, 1.0, 4.0, 4.0}, 1.0, 4294967295), 1, 1), 4294967295), "border corner once")
    check(equals(C.pixel(C.circle(base(), 3.0, 3.0, 2.0, 4294967295), 3, 3), 4294967295), "circle centre")
    check(equals(C.pixel(C.circle(base(), 3.0, 3.0, 2.0, 4294967295), 1, 1), 255), "circle corner outside")
    check(absent(C.pixel(base(), 8, 0)), "no modular out-of-bounds read")
    check(output_leaf(C.finish(C.new(1, 1, 1.0, 287454207)), 1122867), "finish converts RGBA to Base RGB")
    check(output_quadrants(C.finish(four_colors())), "finish preserves all four quadrants")
    check(output_leaf(C.finish(C.fill_rect(C.new(1, 1, 1.0, 255), G.Rect{0.0, 0.0, 1.0, 1.0}, 4278190208)), 8388608), "finish resolves alpha before RGB output")
    check(equals(C.pixel(quadrants(), 7, 0), 4278190335), "top-right quadrant")
    check(equals(C.pixel(quadrants(), 0, 5), 16711935), "bottom-left quadrant")
    check(equals(C.pixel(quadrants(), 7, 5), 65535), "bottom-right quadrant and nonsquare surface")
    check(failed(C.fill_rect(base(), G.Rect{(0.0 / 0.0 : F32), 0.0, 1.0, 1.0}, 255)), "NaN coordinate rejected")
    check(failed(C.new(8, 4, (1.0 / 0.0 : F32), 255)), "infinite scale rejected")
    check(first_error(C.stroke_rect(C.Failed{"first"}, G.Rect{0.0, 0.0, 1.0, 1.0}, F32.neg(1.0), 255)), "builder keeps first error")
    check(equals(C.pixel(C.blit_mask(C.new(8, 8, 2.0, 255), 1.0, 1.0, 1, 1, [255], 4294967295), 2, 2), 4294967295), "mask origin scales")
    check(equals(C.pixel(C.blit_mask(C.new(8, 8, 2.0, 255), 1.0, 1.0, 1, 1, [255], 4294967295), 3, 2), 255), "mask samples remain physical pixels")
    check(same_result(R.pixels.of(drawn.canvas()), R.pixels(drawn.scene())),
      "draw list: replaying a scene equals drawing the same calls on the canvas (1200 pixels)")
    check(U32.is_eq(S.count(drawn.scene()), 8), "draw list: one operation per visible fill, mask and bitmap")
    check(scene_failed(S.new(0, 4, 1.0, 255)) && scene_failed(S.new(4, 4, 1.0, 0)), "draw list: surface validation")
    check(scene_failed(S.fill_rect(S.new(8, 8, 1.0, 255), G.Rect{0.0, 0.0, F32.neg(1.0), 1.0}, 255)), "draw list: invalid rectangle")
    check(scene_failed(S.blit_mask(S.new(8, 8, 1.0, 255), 1, 0.0, 0.0, 2, 1, [255], 255)), "draw list: short mask rejected")
    check(U32.is_eq(S.count(S.fill_rect(S.new(8, 8, 1.0, 255), G.Rect{1.0, 1.0, 2.0, 2.0}, 4294967040)), 0),
      "draw list: a transparent fill records nothing")
    check(same_words(first_op(S.fill_rect(S.clip_rect(S.new(8, 8, 1.0, 255), G.Rect{2.0, 2.0, 3.0, 3.0}),
      G.Rect{0.0, 0.0, 8.0, 8.0}, 255)), [2, 2, 5, 5]), "draw list: fills are resolved against the clip")
    check(same_words(first_op(S.round_rect(S.new(64, 64, 2.0, 255), G.Rect{1.25, 2.0, 10.0, 4.0}, 9.0, 255)),
      [20, 32, 180, 96, 32, 0]), "draw list: rounded box in eighths, radius clamped to half the shorter side")
    check(same_words(first_op(S.border(S.new(64, 64, 1.0, 255), G.Rect{0.0, 0.0, 10.0, 10.0}, 2.0, 1.5, 255)),
      [0, 0, 80, 80, 16, 12]), "draw list: border width in eighths")
    check(U32.is_eq(S.count(S.border(S.new(64, 64, 1.0, 255), G.Rect{0.0, 0.0, 10.0, 10.0}, 2.0, 0.01, 255)), 0),
      "draw list: a border thinner than 1/8 pixel draws nothing")
    check(U32.is_eq(R.coverage(1, 1, 0, 0, 80, 80, 16, 0), 255) && U32.is_eq(R.coverage(20, 1, 0, 0, 80, 80, 16, 0), 0),
      "coverage: inside and outside")
    check(U32.is_eq(R.coverage(0, 0, 0, 0, 80, 80, 16, 0), 96), "coverage: a rounded corner pixel is partial (6 of 16 samples)")
    check(U32.is_eq(R.coverage(5, 5, 0, 0, 80, 80, 16, 12), 0) && U32.is_eq(R.coverage(0, 5, 0, 0, 80, 80, 16, 12), 255),
      "coverage: a ring is empty inside its border")
    check(U32.is_eq(R.coverage(0, 0, 4294967288, 4294967288, 8, 8, 0, 0), 255), "coverage: boxes left of and above the origin")
    check(same_result(R.pixels(drawn.scene()), R.pixels(via_pixels(S.coverage(1, 7, 5, ramp(35)), S.rgba(2, 5, 6, rgba(30))))),
      "draw list: pixels validated once draw like the validating blits")
    check(pixels_failed(S.coverage(1, 2, 1, [255])) && pixels_failed(S.coverage(1, 1, 1, [256])) &&
      Bool.not(pixels_failed(S.rgba(1, 1, 1, [4294967295]))), "draw list: pixels are validated when made")
    IO.print("60 checks passed; this is runtime testing, not a proof of the complete system")
