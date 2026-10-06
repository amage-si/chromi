import Base
import ./main.bend as C
import ./geometry.bend as G
import ./color.bend as Color

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
    IO.print("44 checks passed; this is runtime testing, not a proof of the complete system")
