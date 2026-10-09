import Base
import ./main.bend as C
import ./geometry.bend as G
import ./color.bend as Color
import ./scene.bend as S
import ./replay.bend as R
import ./frame.bend as F
import ./mix.bend as M

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

# Retained frames
# ---------------

def frame_bg() -> U32:
  336860415

# What the test frames show.
type Setup is Data:
  Setup{hover: Bool, focus: Bool, overlay: F32, picture: Bool, extra: Bool, swapped: Bool,
    width: U32, height: U32}

def setup() -> Setup:
  Setup{False{}, False{}, 30.0, True{}, False{}, False{}, 64, 40}

def with_hover(l: Setup) -> Setup:
  Setup{h, f, o, p, e, s, w, hh} = l
  Setup{True{}, f, o, p, e, s, w, hh}

def with_focus(l: Setup) -> Setup:
  Setup{h, f, o, p, e, s, w, hh} = l
  Setup{h, True{}, o, p, e, s, w, hh}

def moved(l: Setup) -> Setup:
  Setup{h, f, o, p, e, s, w, hh} = l
  Setup{h, f, 5.0, p, e, s, w, hh}

def changed_set(l: Setup) -> Setup:
  Setup{h, f, o, p, e, s, w, hh} = l
  Setup{h, f, o, False{}, True{}, s, w, hh}

def swapped(l: Setup) -> Setup:
  Setup{h, f, o, p, e, s, w, hh} = l
  Setup{h, f, o, p, e, True{}, w, hh}

def resized(l: Setup) -> Setup:
  Setup{h, f, o, p, e, s, w, hh} = l
  Setup{h, f, o, p, e, s, 70, 44}

def paint.panel(s: S.Scene) -> S.Scene:
  S.border(S.round_rect(s, G.Rect{4.0, 4.0, 56.0, 32.0}, 6.0, 354033919), G.Rect{4.0, 4.0, 56.0, 32.0},
    6.0, 1.0, 825901311)

def ring(focus: Bool, s: S.Scene) -> S.Scene:
  match focus:
    case True{}:
      S.border(s, G.Rect{11.0, 11.0, 22.0, 10.0}, 2.0, 1.0, 2764636159)
    case False{}:
      s

def paint.button(+hover: Bool, focus: Bool, s: S.Scene) -> S.Scene:
  ring(focus, S.round_rect(s, G.Rect{10.0, 10.0, 24.0, 12.0}, 3.0, Bool.pick(U32, hover, 829482751, 610062079)))

def paint.label(s: S.Scene) -> S.Scene:
  S.blit_mask(s, 1, 12.0, 13.0, 8, 6, ramp(48), 4294967295)

def paint.overlay(+x: F32, s: S.Scene) -> S.Scene:
  S.fill_rect(s, G.Rect{x, 8.0, 20.0, 20.0}, 2164195456)

def paint.picture(s: S.Scene) -> S.Scene:
  S.blit_rgba(s, 2, 40.0, 24.0, 6, 5, rgba(30))

def middle(swap: Bool, +hover: Bool, +focus: Bool, +x: F32, b: F.Build) -> F.Build:
  match swap:
    case False{}:
      F.part(F.part(b, 2, s => paint.label(paint.button(hover, focus, s))), 4, s => paint.overlay(x, s))
    case True{}:
      F.part(F.part(b, 4, s => paint.overlay(x, s)), 2, s => paint.label(paint.button(hover, focus, s)))

def picture.part(on: Bool, b: F.Build) -> F.Build:
  match on:
    case True{}:
      F.part(b, 5, s => paint.picture(s))
    case False{}:
      b

def extra.part(on: Bool, b: F.Build) -> F.Build:
  match on:
    case True{}:
      F.part(b, 6, s => S.fill_rect(s, G.Rect{2.0, 30.0, 12.0, 6.0}, 4278190335))
    case False{}:
      b

def framed(l: Setup, last: F.Frame) -> F.Frame:
  Setup{+hover, +focus, +x, pic, more, swap, +w, +h} = l
  b = F.begin(last, w, h, 1.0, frame_bg())
  b = F.part(b, 1, s => paint.panel(s))
  b = middle(swap, hover, focus, x, b)
  b = picture.part(pic, b)
  F.end(extra.part(more, b))

# The same calls as one scene.
def scene.of_setup() -> S.Scene:
  paint.picture(paint.overlay(30.0, paint.label(paint.button(False{}, False{},
    paint.panel(S.new(64, 40, 1.0, frame_bg()))))))

# A frame as a renderer leaves it: its parts, no damage.
def settle(+f: F.Frame) -> F.Frame:
  F.drawn(f, F.parts(f))

def same_ops.of(a: Result<&1, &1, U32 & String, List<&2, S.Op>>, b: Result<&1, &1, U32 & String, List<&2, S.Op>>) -> Bool:
  match a b:
    case Done{x} Done{y}:
      S.same_ops(x, y)
    case _ _:
      False{}

def same_pixels(+n: Nat, a: Result<&1, &1, U32 & String, Array<U32>>, b: Result<&1, &1, U32 & String, Array<U32>>) -> Bool:
  match a b:
    case Done{x} Done{y}:
      same_arrays(n, Array.get(U32, x, 0), Array.get(U32, y, 0), 0)
    case _ _:
      False{}

def pixels_of(size: U32 & U32) -> Nat:
  (w, h) = size
  U32.to_nat((w * h : U32))

def has_regions(+f: F.Frame) -> Bool:
  Bool.not(List.is_empty(&2, G.Box, F.regions(f)))

# Repainting only the damage of `next` over the picture of `last` equals
# painting `next` whole, and `next` is drawn partly (not whole, some damage,
# less than all of it).
def repaints(+last: F.Frame, +next: F.Frame) -> Bool:
  same_pixels(pixels_of(F.size(next)), R.pixels.of(R.repaint(R.frame_canvas(last), next)),
    R.pixels.of(R.frame_canvas(next)))

def partly(+f: F.Frame) -> Bool:
  Bool.not(F.whole(f)) && Bool.not(List.is_empty(&2, G.Box, F.regions(f))) &&
    U32.is_lt(F.area(F.regions(f), 0), (64 * 40 : U32))

def box_words(bs: List<&2, G.Box>) -> List<&2, U32>:
  match bs:
    case Nil{}:
      Nil{}
    case Con{G.Box{x, y, r, b}, rest}:
      x <> y <> r <> b <> box_words(rest)

def damaged(ds: List<&2, G.Box>) -> F.Frame:
  F.Frame{64, 40, 1.0, frame_bg(), Nil{}, ds, False{}}

def stamped.frame(+stamp: U32, +color: U32, last: F.Frame) -> F.Frame:
  F.end(F.stamped(F.begin(last, 64, 40, 1.0, frame_bg()), 7, stamp,
    s => S.fill_rect(s, G.Rect{0.0, 0.0, 10.0, 10.0}, color)))

def blank8() -> S.Scene:
  S.new(8, 8, 1.0, 255)

# Colour interpolation (mix.bend)
# --------------------------------

type Space is Data:
  InOklab{}
  InLinear{}
  InSrgb{}

def mix_in(space: Space, +a: U32, +b: U32, +t: F32) -> U32:
  match space:
    case InOklab{}:
      M.mix_oklab(a, b, t)
    case InLinear{}:
      M.mix_linear(a, b, t)
    case InSrgb{}:
      M.mix_srgb(a, b, t)

def diff(+x: U32, +y: U32) -> U32:
  (U32.max(x, y) - U32.min(x, y) : U32)

# The largest difference of one channel (alpha included) between two colours.
def channel_error(+c: U32, +d: U32) -> U32:
  U32.max(U32.max(diff(Color.red(c), Color.red(d)), diff(Color.green(c), Color.green(d))),
    U32.max(diff(Color.blue(c), Color.blue(d)), diff(Color.alpha(c), Color.alpha(d))))

# A pair, t, and the mixes in OKLab, linear light and sRGB computed by an
# independent float64 reference (Python, CSS Color 4 premultiplied rules).
type MixCase is Data:
  MixCase{a: U32, b: U32, t: F32, oklab: U32, linear: U32, srgb: U32}

def mix_cases() -> List<&2, MixCase>:
  [MixCase{255, 4278190335, 0.397, 1191182591, 2835349759, 1694499071},
  MixCase{65535, 4294902015, 0.815, 3370288383, 3924391935, 3503304703},
  MixCase{4294902015, 255, 0.581, 1296892159, 2913796351, 1802174719},
  MixCase{862375040, 16711808, 0.047, 812632448, 846514304, 829276800},
  MixCase{4278190080, 4278190080, 0.078, 4278190080, 4278190080, 4278190080},
  MixCase{4294902015, 862375040, 0.426, 3285811657, 3756224969, 3369416649},
  MixCase{4294902015, 16711935, 0.628, 2566848767, 2768175359, 1610547455},
  MixCase{65535, 4278190080, 0.059, 65520, 65520, 65520},
  MixCase{949539216, 200071088, 0.556, 684447394, 617665954, 499897762},
  MixCase{571981485, 1243862445, 0.421, 874367149, 924698797, 857524397},
  MixCase{2322228204, 505913792, 0.569, 1330743507, 1699776723, 1380418515},
  MixCase{2406286680, 3505236015, 0.678, 3014616380, 3049225788, 2981190460},
  MixCase{442620898, 2497953762, 0.57, 1538249186, 1958399202, 1621871586},
  MixCase{806899909, 1599435267, 0.105, 806899889, 806899889, 806899889},
  MixCase{3058492450, 269676599, 0.563, 1345842478, 1848568878, 1176890414},
  MixCase{2658625969, 884585905, 0.496, 2123993009, 2023527857, 1771605937},
  MixCase{2283721058, 1836494974, 0.772, 1953216376, 1936504696, 1919334008},
  MixCase{1999744784, 2514969041, 0.915, 2514903745, 2514903745, 2514903745},
  MixCase{1552984408, 1287489368, 0.253, 1503437400, 1486725464, 1486594136},
  MixCase{772092314, 3002158228, 0.774, 2494976917, 2681620373, 2478458517},
  MixCase{351564607, 2467131055, 0.304, 2458351713, 1890349153, 1517645921},
  MixCase{2126508550, 3758686726, 0.347, 3029838598, 2845755398, 2692783878},
  MixCase{1927728186, 1236683272, 0.607, 1792980764, 1826602268, 1809757468},
  MixCase{314395342, 507088656, 0.512, 229922413, 330781293, 330518381},
  MixCase{708506836, 3251895508, 0.345, 1417345748, 2072704980, 1584396244},
  MixCase{4008365026, 2100080514, 0.423, 3417688249, 3586769849, 3434267577},
  MixCase{4131840500, 2869965264, 0.086, 4031042801, 4047821553, 4030911729},
  MixCase{2396917114, 2461127546, 0.783, 2428352890, 2445065594, 2444994682},
  MixCase{3514800842, 1347535308, 0.343, 2759043787, 2993859019, 2758780875},
  MixCase{1504004731, 2552799181, 0.497, 2338686884, 2238613412, 2153217956},
  MixCase{3422624989, 1959387101, 0.077, 3392025053, 3342617053, 3306171357},
  MixCase{401991735, 4057374422, 0.275, 3169173091, 3236151395, 2581838947},
  MixCase{2993772869, 2852512026, 0.074, 2993708610, 2993643842, 2993577282},
  MixCase{3140305423, 3012885263, 0.313, 3159850255, 3109985551, 3092085775},
  MixCase{2482260147, 4265314571, 0.678, 2883868481, 2766689089, 2682212161},
  MixCase{1914012528, 1222328495, 0.712, 1706516893, 1405506461, 1370640029},
  MixCase{3809809032, 2871841672, 0.35, 3459542152, 3525280904, 3474806408},
  MixCase{4040054837, 1982966162, 0.358, 2708970326, 3012333654, 2792327510},
  MixCase{2623879480, 502922616, 0.494, 2076884312, 1624758104, 1187626584},
  MixCase{937195259, 3299535611, 0.292, 1993383419, 2026873851, 1624086779}]

def wanted(space: Space, +oklab: U32, +linear: U32, +srgb: U32) -> U32:
  match space:
    case InOklab{}:
      oklab
    case InLinear{}:
      linear
    case InSrgb{}:
      srgb

# The worst channel error against the reference.
def reference.worst(+space: Space, xs: List<&2, MixCase>, +acc: U32) -> U32:
  match xs:
    case Nil{}:
      acc
    case Con{MixCase{a, b, t, o, l, s}, rest}:
      reference.worst(space, rest, U32.max(acc, channel_error(mix_in(space, a, b, t), wanted(space, o, l, s))))

# Exact ends at t = 0 and 1, and t clamped outside (NaN counts as 0).
def ends_exact(+space: Space, +a: U32, +b: U32) -> Bool:
  U32.is_eq(mix_in(space, a, b, 0.0), a) && U32.is_eq(mix_in(space, a, b, 1.0), b) &&
    U32.is_eq(mix_in(space, a, b, F32.neg(0.5)), a) && U32.is_eq(mix_in(space, a, b, 2.0), b) &&
    U32.is_eq(mix_in(space, a, b, (0.0 / 0.0 : F32)), a)

def endpoints(+space: Space, xs: List<&2, MixCase>) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case Con{MixCase{a, b, t, o, l, s}, rest}:
      ends_exact(space, a, b) && endpoints(space, rest)

# mix(a, b, t) and mix(b, a, 1 - t): the worst channel difference.
def symmetry.worst(+space: Space, xs: List<&2, MixCase>, +acc: U32) -> U32:
  match xs:
    case Nil{}:
      acc
    case Con{MixCase{+a, +b, +t, o, l, s}, rest}:
      symmetry.worst(space, rest, U32.max(acc, channel_error(mix_in(space, a, b, t), mix_in(space, b, a, (1.0 - t : F32)))))

# sRGB -> OKLab -> sRGB on every 61st opaque colour of the 2^24 (all the
# greys separately): the worst channel error.
def round_trip.worst(n: Nat, +c: U32, +step: U32, +acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+p:
      +rgba = ((c << 8n) .|. 255 : U32)
      round_trip.worst(p, (c + step : U32), step, U32.max(acc, channel_error(rgba, M.to_rgba(M.of_rgba(rgba), 255))))

def near(+x: F32, +y: F32) -> Bool:
  (F32.abs((x - y : F32)) < 0.001 : F32)

# OKLab of sRGB red (Ottosson's reference: 0.62796, 0.22486, 0.12585) and white.
def lab_is(v: M.Lab, +l: F32, +a: F32, +b: F32) -> Bool:
  match v:
    case M.Lab{x, y, z}:
      near(x, l) && near(y, a) && near(z, b)

def lch_hue(v: M.Lch) -> F32:
  match v:
    case M.Lch{l, c, h}:
      h

# Blue to yellow at 0.5 in OKLab keeps chroma: not a grey.
def not_grey(+c: U32) -> Bool:
  Bool.not(U32.is_eq(Color.red(c), Color.blue(c)) && U32.is_eq(Color.green(c), Color.blue(c)))

def hex.go(n: Nat, +c: U32, acc: String) -> String:
  match n:
    case 0n:
      acc
    case 1n+p:
      +d = (c .&. 15 : U32)
      hex.go(p, (c >> 4n : U32), SCon{Char.from_u32((d + Bool.pick(U32, U32.is_lt(d, 10), 48, 87) : U32)), acc})

def hex(+c: U32) -> String:
  "0x" ++ hex.go(8n, c, "")

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
    check(U32.is_eq(S.count(S.blit_mask(blank8(), 1, 20.0, 2.0, 2, 2, [255, 255, 255, 255], 255)), 0) &&
      U32.is_eq(S.count(S.blit_mask(S.clip_rect(blank8(), G.Rect{0.0, 0.0, 4.0, 4.0}), 1, 5.0, 5.0, 2, 2,
        [255, 255, 255, 255], 255)), 0) &&
      U32.is_eq(S.count(S.blit_rgba(blank8(), 2, F32.neg(3.0), 0.0, 2, 2, [255, 255, 255, 255])), 0),
      "culling: masks and bitmaps outside the surface or the clip are not recorded")
    check(U32.is_eq(S.count(S.blit_mask(blank8(), 1, 7.0, 7.0, 2, 2, [255, 255, 255, 255], 255)), 1) &&
      U32.is_eq(S.count(S.round_rect(blank8(), G.Rect{F32.neg(20.0), 0.0, 10.0, 4.0}, 2.0, 255)), 0) &&
      U32.is_eq(S.count(S.round_rect(blank8(), G.Rect{F32.neg(1.9), 0.0, 2.0, 4.0}, 0.5, 255)), 1),
      "culling: partly visible content is kept; a rounded box outside is not recorded")
    check(S.visible(blank8(), G.Rect{6.5, 6.5, 4.0, 4.0}) && Bool.not(S.visible(blank8(), G.Rect{8.0, 0.0, 2.0, 2.0})) &&
      Bool.not(S.visible(S.clip_rect(blank8(), G.Rect{0.0, 0.0, 2.0, 2.0}), G.Rect{3.0, 3.0, 1.0, 1.0})),
      "culling: visible tells whether a box can show inside the clip")
    check(same_ops.of(F.ops(framed(setup(), F.none())), S.ops(scene.of_setup())) &&
      same_pixels(2560n, R.pixels.of(R.frame_canvas(framed(setup(), F.none()))), R.pixels(scene.of_setup())),
      "frames: a frame's parts in order are the draw list of the same calls (2560 pixels)")
    check(F.whole(framed(setup(), F.none())) && Bool.not(has_regions(framed(setup(), settle(framed(setup(), F.none()))))) &&
      Bool.not(F.whole(framed(setup(), settle(framed(setup(), F.none()))))),
      "frames: the first frame is whole; the same frame again keeps every part and damages nothing")
    check(same_words(box_words(F.regions(damaged([G.Box{0, 0, 10, 10}, G.Box{5, 5, 15, 15}, G.Box{30, 30, 35, 35},
      G.Box{60, 35, 80, 50}]))), [60, 35, 64, 40, 0, 0, 15, 15, 30, 30, 35, 35]),
      "frames: damage regions join where they meet and stay within the surface")
    check(same_ops.of(F.ops(stamped.frame(1, 65535, settle(stamped.frame(1, 4278190335, F.none())))),
      F.ops(stamped.frame(1, 4278190335, F.none()))) &&
      Bool.not(has_regions(stamped.frame(1, 65535, settle(stamped.frame(1, 4278190335, F.none()))))) &&
      has_regions(stamped.frame(2, 65535, settle(stamped.frame(1, 4278190335, F.none())))),
      "frames: a stamped part with the same stamp is kept without recording it; a new stamp records it")
    check(partly(framed(with_hover(setup()), settle(framed(setup(), F.none())))) &&
      repaints(settle(framed(setup(), F.none())), framed(with_hover(setup()), settle(framed(setup(), F.none())))),
      "repaint: hover (a button's color under a translucent overlay) equals the frame painted whole")
    check(partly(framed(with_focus(setup()), settle(framed(setup(), F.none())))) &&
      repaints(settle(framed(setup(), F.none())), framed(with_focus(setup()), settle(framed(setup(), F.none())))),
      "repaint: focus (a ring added to the button) equals the frame painted whole")
    check(partly(framed(moved(setup()), settle(framed(setup(), F.none())))) &&
      repaints(settle(framed(setup(), F.none())), framed(moved(setup()), settle(framed(setup(), F.none())))),
      "repaint: a translucent part moved over others equals the frame painted whole")
    check(partly(framed(changed_set(setup()), settle(framed(setup(), F.none())))) &&
      repaints(settle(framed(setup(), F.none())), framed(changed_set(setup()), settle(framed(setup(), F.none())))),
      "repaint: a part removed and another added equal the frame painted whole")
    check(partly(framed(swapped(setup()), settle(framed(setup(), F.none())))) &&
      repaints(settle(framed(setup(), F.none())), framed(swapped(setup()), settle(framed(setup(), F.none())))),
      "repaint: overlapping parts drawn in another order equal the frame painted whole")
    check(F.whole(framed(resized(setup()), settle(framed(setup(), F.none())))) &&
      repaints(settle(framed(setup(), F.none())), framed(resized(setup()), settle(framed(setup(), F.none())))),
      "repaint: a new size is painted whole")
    check(Bool.not(repaints(settle(framed(setup(), F.none())),
      settle(framed(with_hover(setup()), settle(framed(setup(), F.none())))))),
      "repaint: control: without its damage the last picture stays, and differs from the new frame")
    check(U32.is_eq(round_trip.worst(275037n, 0, 61, 0), 0) && U32.is_eq(round_trip.worst(256n, 0, 65793, 0), 0),
      "mix: sRGB -> OKLab -> sRGB is exact on 275,293 colours (every 61st of 2^24 and every grey)")
    check(lab_is(M.of_rgba(4278190335), 0.62796, 0.22486, 0.12585) && lab_is(M.of_rgba(4294967295), 1.0, 0.0, 0.0) &&
      lab_is(M.of_rgba(255), 0.0, 0.0, 0.0), "mix: OKLab of red, white and black")
    check(U32.is_eq(M.to_rgba(M.oklch_to_oklab(M.oklch(M.of_rgba(4278190335))), 255), 4278190335) &&
      near(lch_hue(M.oklch(M.of_rgba(4278190335))), 0.51023), "mix: OKLCH of red (hue 29 degrees) and back")
    check(U32.is_le(reference.worst(InOklab{}, mix_cases(), 0), 1) && U32.is_le(reference.worst(InLinear{}, mix_cases(), 0), 1) &&
      U32.is_le(reference.worst(InSrgb{}, mix_cases(), 0), 1), "mix: 40 mixes in each space within 1 of a float64 reference")
    IO.print("     worst channel error against the reference: oklab " ++ U32.show(reference.worst(InOklab{}, mix_cases(), 0)) ++
      ", linear " ++ U32.show(reference.worst(InLinear{}, mix_cases(), 0)) ++ ", srgb " ++ U32.show(reference.worst(InSrgb{}, mix_cases(), 0)))
    check(endpoints(InOklab{}, mix_cases()) && endpoints(InLinear{}, mix_cases()) && endpoints(InSrgb{}, mix_cases()),
      "mix: exact ends at t = 0 and 1; t clamped outside 0..1; NaN gives the start")
    check(U32.is_le(symmetry.worst(InOklab{}, mix_cases(), 0), 1) && U32.is_le(symmetry.worst(InLinear{}, mix_cases(), 0), 1) &&
      U32.is_le(symmetry.worst(InSrgb{}, mix_cases(), 0), 1), "mix: mix(a, b, t) equals mix(b, a, 1 - t) within 1")
    check(U32.is_eq(M.mix_oklab(4278190335, 0, 0.5), 4278190208) && U32.is_eq(M.mix_linear(4278190335, 0, 0.5), 4278190208) &&
      U32.is_eq(M.mix_srgb(4278190335, 0, 0.5), 4278190208), "mix: red to transparent stays red at half alpha (premultiplied, no dark fringe)")
    check(U32.is_eq(M.mix_oklab(4278190080, 65535, 0.25), 65344) && U32.is_eq(M.mix_linear(4278190080, 65535, 0.25), 65344),
      "mix: alpha is linear in t and the colour comes from the visible end")
    check(U32.is_eq(M.mix_oklab(65535, 4294902015, 0.5), 1823197183) && not_grey(M.mix_oklab(65535, 4294902015, 0.5)) &&
      U32.is_eq(M.mix_srgb(65535, 4294902015, 0.5), 2155905279), "mix: blue to yellow at 0.5 in OKLab is not the sRGB grey")
    IO.print("     blue + yellow at 0.5: oklab " ++ hex(M.mix_oklab(65535, 4294902015, 0.5)) ++ ", linear " ++
      hex(M.mix_linear(65535, 4294902015, 0.5)) ++ ", srgb " ++ hex(M.mix_srgb(65535, 4294902015, 0.5)))
    IO.print("82 checks passed; this is runtime testing, not a proof of the complete system")
