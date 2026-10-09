import Base
import ./geometry.bend as G
import ./scene.bend as S
import ./replay.bend as R
import ./gpu.bend as Gpu
import ./frame.bend as F
import ../Voltra/gpu.bend as V
import ../Voltra/atlas.bend as At

# The GPU path against the CPU reference: each scene is painted by
# replay.bend on the CPU and drawn by Voltra offscreen, read back, and the
# two are compared pixel by pixel. Needs a Vulkan 1.3 GPU (no display) and
# Voltra beside Chromi.

def width() -> U32:
  320

def height() -> U32:
  200

def check(ok: Bool, message: String) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("PASS " ++ message)
    case False{}:
      IO.die(Unit, 1, "FAIL " ++ message)

# Comparison
# ----------

type Diff is Data:
  Diff{count: U32, worst: U32, first: U32}

def byte(+c: U32, +shift: Nat) -> U32:
  ((c >> shift) .&. 255 : U32)

def absdiff(+a: U32, +b: U32) -> U32:
  (U32.max(a, b) - U32.min(a, b) : U32)

def worst(+a: U32, +b: U32) -> U32:
  U32.max(U32.max(absdiff(byte(a, 24n), byte(b, 24n)), absdiff(byte(a, 16n), byte(b, 16n))),
    U32.max(absdiff(byte(a, 8n), byte(b, 8n)), absdiff(byte(a, 0n), byte(b, 0n))))

def tally(d: Diff, +i: U32, +got: U32, +want: U32) -> Diff:
  Diff{+n, w, f} = d
  +off = U32.is_ne(got, want)
  Diff{(n + Bool.to_u32(off) : U32), U32.max(w, worst(got, want)),
    Bool.pick(U32, off && U32.is_eq(n, 0), i, f)}

def compare(n: Nat, a: Array<U32> & U32, b: Array<U32> & U32, +i: U32, d: Diff) -> Diff:
  match n:
    case 0n:
      d
    case 1n+p:
      (xa, +ga) = a
      (xb, +gb) = b
      +j = (i + 1 : U32)
      compare(p, Array.get(U32, xa, j), Array.get(U32, xb, j), j, tally(d, i, ga, gb))

def compare.ref(gpu: Array<U32>, cpu: Result<&1, &1, U32 & String, Array<U32>>) -> Diff:
  match cpu:
    case Fail{e}:
      Diff{0, 0, 0}
    case Done{ref}:
      compare(U32.to_nat((width() * height() : U32)), Array.get(U32, gpu, 0), Array.get(U32, ref, 0), 0, Diff{0, 0, 0})

def control.verdict(d: Diff, +total: U32) -> IO(Unit):
  Diff{+n, w, f} = d
  check(U32.is_gt(n, 0), "control: a different scene's reference differs in " ++ U32.show(n) ++ " of " ++
    U32.show(total) ++ " pixels")

def verdict(d: Diff, +total: U32, name: String) -> IO(Unit):
  Diff{+n, +w, +f} = d
  check(U32.is_eq(n, 0), name ++ ": " ++ U32.show(n) ++ " of " ++ U32.show(total) ++
    " pixels differ, max channel difference " ++ U32.show(w) ++
    Bool.pick(String, U32.is_eq(n, 0), "", " (first at " ++ U32.show((f % width() : U32)) ++ "," ++
      U32.show((f / width() : U32)) ++ ")"))

def compared(gpu: Array<U32>, cpu: Result<&1, &1, U32 & String, Array<U32>>, name: String) -> IO(Unit):
  match cpu:
    case Fail{(code, message)}:
      IO.die(Unit, 1, "FAIL " ++ name ++ ": the CPU reference failed: " ++ message)
    case Done{ref}:
      +total = (width() * height() : U32)
      verdict(compare(U32.to_nat(total), Array.get(U32, gpu, 0), Array.get(U32, ref, 0), 0, Diff{0, 0, 0}),
        total, name)

# Scenes
# ------

def base() -> S.Scene:
  S.new(width(), height(), 1.0, 336860415)

# Canvas features: fills, borders, clips, translucency, fractional edges.
def shapes() -> S.Scene:
  s = S.fill_rect(base(), G.Rect{12.0, 10.0, 140.0, 80.0}, 1089715967)
  s = S.stroke_rect(s, G.Rect{12.0, 10.0, 140.0, 80.0}, 3.0, 4294967295)
  s = S.fill_rect(s, G.Rect{40.5, 30.25, 200.0, 60.7}, 2164195456)
  s = S.clip_rect(s, G.Rect{100.0, 20.0, 150.0, 150.0})
  s = S.fill_rect(s, G.Rect{0.0, 0.0, 320.0, 200.0}, 4278190208)
  s = S.reset_clip(s)
  S.fill_rect(s, G.Rect{F32.neg(10.0), 150.0, 60.0, 80.0}, 16744447)

# Rounded boxes and borders at fractional positions, clipped, over each other.
def rounded() -> S.Scene:
  s = S.round_rect(base(), G.Rect{10.3, 12.6, 120.0, 44.0}, 10.0, 610062079)
  s = S.border(s, G.Rect{10.3, 12.6, 120.0, 44.0}, 10.0, 2.0, 2764636159)
  s = S.round_rect(s, G.Rect{150.0, 20.0, 60.0, 60.0}, 30.0, 2868903808)
  s = S.border(s, G.Rect{140.75, 30.5, 150.0, 120.25}, 24.5, 6.25, 1086374143)
  s = S.clip_rect(s, G.Rect{20.0, 100.0, 90.0, 70.0})
  s = S.round_rect(s, G.Rect{F32.neg(30.0), 80.0, 120.0, 140.0}, 40.0, 4294902015)
  s = S.reset_clip(s)
  S.border(s, G.Rect{200.0, 160.0, 100.0, 30.0}, 0.0, 1.0, 4294967295)

# Coverage gradient: value (x * 255 / w + y) % 256.
def ramp.go(n: Nat, +i: U32, +w: U32) -> List<&2, U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      ((((i % w : U32) * 255 / w : U32) + i / w) % 256 : U32) <> ramp.go(p, (i + 1 : U32), w)

def ramp(+w: U32, +h: U32) -> List<&2, U32>:
  ramp.go(U32.to_nat((w * h : U32)), 0, w)

# RGBA test image: every channel varies, alpha covers 0..255.
def picture.go(n: Nat, +i: U32, +w: U32) -> List<&2, U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      +x = (i % w : U32)
      +y = (i / w : U32)
      (((x * 4 % 256 : U32) << 24n) .|. ((y * 5 % 256 : U32) << 16n) .|. (((x + y) % 256 : U32) << 8n) .|.
        ((x * 3 + y * 7) % 256 : U32) : U32) <> picture.go(p, (i + 1 : U32), w)

def picture(+w: U32, +h: U32) -> List<&2, U32>:
  picture.go(U32.to_nat((w * h : U32)), 0, w)

# Masks and bitmaps: clipped, partly off the surface, translucent ink.
def textures() -> S.Scene:
  s = S.blit_mask(base(), 1, 10.0, 10.0, 100, 60, ramp(100, 60), 4294967295)
  s = S.blit_mask(s, 2, 60.0, 40.0, 80, 40, ramp(80, 40), 4282664064)
  s = S.blit_rgba(s, 3, 150.0, 20.0, 64, 64, picture(64, 64))
  s = S.clip_rect(s, G.Rect{170.0, 100.0, 100.0, 50.0})
  s = S.blit_rgba(s, 4, 160.0, 90.0, 120, 80, picture(120, 80))
  s = S.reset_clip(s)
  s = S.blit_mask(s, 1, F32.neg(30.0), 140.0, 100, 60, ramp(100, 60), 2868903935)
  S.blit_rgba(s, 3, 280.0, 170.0, 64, 64, picture(64, 64))

# Everything at once, the way a UI frame mixes it.
def mixed() -> S.Scene:
  s = S.fill_rect(base(), G.Rect{16.0, 16.0, 288.0, 168.0}, 354033919)
  s = S.round_rect(s, G.Rect{30.0, 120.0, 130.0, 44.0}, 8.0, 610062079)
  s = S.border(s, G.Rect{28.0, 118.0, 134.0, 48.0}, 10.0, 2.0, 2764636159)
  s = S.clip_rect(s, G.Rect{38.0, 124.0, 114.0, 36.0})
  s = S.blit_mask(s, 1, 44.0, 128.0, 100, 60, ramp(100, 60), 4294967295)
  s = S.reset_clip(s)
  s = S.blit_rgba(s, 3, 200.0, 40.0, 64, 64, picture(64, 64))
  s = S.fill_rect(s, G.Rect{30.0, 30.0, 150.0, 6.0}, 1089715967)
  S.blit_mask(s, 2, 180.0, 120.0, 80, 40, ramp(80, 40), 4286595200)

# Retained frames
# ---------------
#
# Frames of parts (frame.bend) rendered by `Gpu.render`: after the first,
# each one redraws only its damage on Voltra's canvas; the readback must
# equal the CPU reference of the whole frame. Keys mean the same pixels as
# in the scenes above (1: ramp(100, 60), 3: picture(64, 64)).

# `glyph` adds a mask with a key the atlas has not seen (uploaded inside a
# partial frame); `big` a 1024x850 mask mostly off the surface that does not
# fit in the atlas left, so the atlas starts over in that frame.
type Setup is Data:
  Setup{hover: Bool, focus: Bool, overlay: F32, extra: Bool, glyph: Bool, big: Bool, width: U32,
    height: U32}

def setup() -> Setup:
  Setup{False{}, False{}, 150.0, False{}, False{}, False{}, 320, 200}

def with_hover(l: Setup) -> Setup:
  Setup{h, f, o, e, gl, bg, w, hh} = l
  Setup{True{}, f, o, e, gl, bg, w, hh}

def with_focus(l: Setup) -> Setup:
  Setup{h, f, o, e, gl, bg, w, hh} = l
  Setup{h, True{}, o, e, gl, bg, w, hh}

def moved(l: Setup) -> Setup:
  Setup{h, f, o, e, gl, bg, w, hh} = l
  Setup{h, f, 20.0, e, gl, bg, w, hh}

def added(l: Setup) -> Setup:
  Setup{h, f, o, e, gl, bg, w, hh} = l
  Setup{h, f, o, True{}, gl, bg, w, hh}

def with_glyph(l: Setup) -> Setup:
  Setup{h, f, o, e, gl, bg, w, hh} = l
  Setup{h, f, o, e, True{}, bg, w, hh}

def with_big(l: Setup) -> Setup:
  Setup{h, f, o, e, gl, bg, w, hh} = l
  Setup{h, f, o, e, gl, True{}, w, hh}

def without_hover(l: Setup) -> Setup:
  Setup{h, f, o, e, gl, bg, w, hh} = l
  Setup{False{}, f, o, e, gl, bg, w, hh}

def resized(l: Setup) -> Setup:
  Setup{h, f, o, e, gl, bg, w, hh} = l
  Setup{h, f, o, e, gl, bg, 240, 150}

def ring(focus: Bool, s: S.Scene) -> S.Scene:
  match focus:
    case True{}:
      S.border(s, G.Rect{28.0, 118.0, 134.0, 48.0}, 10.0, 2.0, 2764636159)
    case False{}:
      s

def paint.button(+hover: Bool, focus: Bool, s: S.Scene) -> S.Scene:
  b = ring(focus, S.round_rect(s, G.Rect{30.0, 120.0, 130.0, 44.0}, 8.0,
    Bool.pick(U32, hover, 829482751, 610062079)))
  c = S.clip_rect(b, G.Rect{38.0, 124.0, 114.0, 36.0})
  S.reset_clip(S.blit_mask(c, 1, 44.0, 128.0, 100, 60, ramp(100, 60), 4294967295))

def extra.part(on: Bool, b: F.Build) -> F.Build:
  match on:
    case True{}:
      F.part(b, 6, s => S.round_rect(s, G.Rect{250.0, 150.0, 50.0, 30.0}, 12.0, 1086374143))
    case False{}:
      b

def glyph.part(on: Bool, b: F.Build) -> F.Build:
  match on:
    case True{}:
      F.part(b, 7, s => S.blit_mask(s, 9, 230.0, 110.0, 30, 20, ramp(30, 20), 4294967295))
    case False{}:
      b

def big.part(on: Bool, b: F.Build) -> F.Build:
  match on:
    case True{}:
      F.part(b, 8, s => S.blit_mask(s, 10, 300.0, 180.0, 1024, 850, ramp(1024, 850), 4282664064))
    case False{}:
      b

def framed(l: Setup, last: F.Frame) -> F.Frame:
  Setup{+hover, +focus, +x, more, gl, bg, +w, +h} = l
  b = F.begin(last, w, h, 1.0, 336860415)
  b = F.part(b, 1, s => S.fill_rect(s, G.Rect{16.0, 16.0, 288.0, 168.0}, 354033919))
  b = F.part(b, 2, s => paint.button(hover, focus, s))
  b = F.part(b, 3, s => S.blit_rgba(s, 3, 200.0, 40.0, 64, 64, picture(64, 64)))
  b = F.part(b, 4, s => S.fill_rect(s, G.Rect{x, 90.0, 120.0, 50.0}, 2164195456))
  b = F.part(b, 5, s => S.blit_mask(s, 1, F32.neg(30.0), 140.0, 100, 60, ramp(100, 60), 2868903935))
  F.end(big.part(bg, glyph.part(gl, extra.part(more, b))))

def verdict.at(d: Diff, +total: U32, +w: U32, name: String) -> IO(Unit):
  Diff{+n, +wd, +f} = d
  check(U32.is_eq(n, 0), name ++ ": " ++ U32.show(n) ++ " of " ++ U32.show(total) ++
    " pixels differ, max channel difference " ++ U32.show(wd) ++
    Bool.pick(String, U32.is_eq(n, 0), "", " (first at " ++ U32.show((f % w : U32)) ++ "," ++
      U32.show((f / w : U32)) ++ ")"))

def compared.at(gpu: Array<U32>, cpu: Result<&1, &1, U32 & String, Array<U32>>, +w: U32, +h: U32,
  name: String) -> IO(Unit):
  match cpu:
    case Fail{(code, message)}:
      IO.die(Unit, 1, "FAIL " ++ name ++ ": the CPU reference failed: " ++ message)
    case Done{ref}:
      +total = (w * h : U32)
      verdict.at(compare(U32.to_nat(total), Array.get(U32, gpu, 0), Array.get(U32, ref, 0), 0, Diff{0, 0, 0}),
        total, w, name)

def rendered.compared(got: Gpu.Renderer & Array<U32>, +want: F.Frame, +w: U32, +h: U32, name: String) ->
  IO(Gpu.Renderer):
  (r, px) = got
  do IO<Gpu.Renderer>:
    compared.at(px, R.pixels.of(R.frame_canvas(want)), w, h, name)
    return r


def rendered.read(got: Gpu.Renderer & F.Frame, +want: F.Frame, +w: U32, +h: U32, name: String) ->
  IO(Gpu.Renderer & F.Frame):
  (+r, drawn) = got
  do IO<Gpu.Renderer & F.Frame>:
    px : Gpu.Renderer & Array<U32> <- Gpu.read(r)
    +r2 : Gpu.Renderer <- rendered.compared(px, want, w, h, name)
    return (r2, drawn)

def rendered(+r: Gpu.Renderer, +f: F.Frame, +w: U32, +h: U32, name: String) -> IO(Gpu.Renderer & F.Frame):
  do IO<Gpu.Renderer & F.Frame>:
    got : Gpu.Renderer & F.Frame <- Gpu.render(r, f)
    rendered.read(got, f, w, h, name)

# The next frame after `prev`, drawn only where it changed.
def step(prev: Gpu.Renderer & F.Frame, l: Setup, +name: String) -> IO(Gpu.Renderer & F.Frame):
  (+r, last) = prev
  +next = framed(l, last)
  +damaged = F.area(F.regions(next), 0)
  do IO<Gpu.Renderer & F.Frame>:
    check(Bool.not(F.whole(next)) && V.kept(Gpu.gpu(r)) && U32.is_gt(damaged, 0) && U32.is_lt(damaged, 64000),
      name ++ ": drawn partly, " ++ U32.show(damaged) ++ " of 64000 pixels damaged")
    rendered(r, next, 320, 200, name)

def step.reset.check(got: Gpu.Renderer & F.Frame, +before: U32) -> IO(Gpu.Renderer & F.Frame):
  (+r, f) = got
  do IO<Gpu.Renderer & F.Frame>:
    check(U32.is_eq(Gpu.resets(r), (before + 1 : U32)), "atlas: that frame started the atlas over (" ++
      U32.show(Gpu.resets(r)) ++ " fresh starts)")
    return (r, f)

# As `step`, and the frame must have started the atlas over.
def step.reset(prev: Gpu.Renderer & F.Frame, l: Setup, +name: String) -> IO(Gpu.Renderer & F.Frame):
  (+r, last) = prev
  +before = Gpu.resets(r)
  do IO<Gpu.Renderer & F.Frame>:
    got : Gpu.Renderer & F.Frame <- step((r, last), l, name)
    step.reset.check(got, before)

def control.at(got: Gpu.Renderer & Array<U32>, +want: F.Frame) -> IO(Gpu.Renderer):
  (r, px) = got
  do IO<Gpu.Renderer>:
    control.verdict(compare.ref(px, R.pixels.of(R.frame_canvas(want))), 64000)
    return r

def stripped.read(got: Gpu.Renderer & F.Frame, +want: F.Frame) -> IO(Gpu.Renderer):
  (r, drawn) = got
  do IO<Gpu.Renderer>:
    px : Gpu.Renderer & Array<U32> <- Gpu.read(r)
    control.at(px, want)


# A control: a changed frame stripped of its damage leaves the last picture,
# which the comparison must see as different.
def stripped(prev: Gpu.Renderer & F.Frame) -> IO(Gpu.Renderer):
  (+r, last) = prev
  +next = framed(with_focus(with_hover(setup())), last)
  do IO<Gpu.Renderer>:
    got : Gpu.Renderer & F.Frame <- Gpu.render(r, F.drawn(next, F.parts(next)))
    stripped.read(got, next)

def resized.step(prev: Gpu.Renderer & F.Frame) -> IO(Gpu.Renderer & F.Frame):
  (+r, last) = prev
  +next = framed(resized(setup()), last)
  do IO<Gpu.Renderer & F.Frame>:
    +r1 : Gpu.Renderer <- Gpu.resize(r, 240, 150)
    check(F.whole(next) && Bool.not(V.kept(Gpu.gpu(r1))), "frames: a new size is drawn whole")
    rendered(r1, next, 240, 150, "frames: the whole frame at a new size, 240x150")

# 4200 one-pixel dots in a 70x60 box: more new quads than the store has
# room for after the first frames (it starts with 4096).
def dots(n: Nat, +i: Nat, s: S.Scene) -> S.Scene:
  match n:
    case 0n:
      s
    case 1n+p:
      +x = Nat.mod(i, 70n)
      +y = Nat.div(i, 70n)
      dots(p, 1n+i, S.fill_rect(s, G.Rect{F32.add(230.0, F32.from_nat(x)), F32.add(20.0, F32.from_nat(y)),
        1.0, 1.0}, Bool.pick(U32, Nat.is_eq(Nat.mod(Nat.add(x, y), 2n), 0n), 4282664191, 4294901759)))

# The frame of `l` with the dots on top.
def dotted(l: Setup, last: F.Frame) -> F.Frame:
  Setup{+hover, +focus, +x, more, gl, bg, +w, +h} = l
  b = F.begin(last, w, h, 1.0, 336860415)
  b = F.part(b, 1, s => S.fill_rect(s, G.Rect{16.0, 16.0, 288.0, 168.0}, 354033919))
  b = F.part(b, 2, s => paint.button(hover, focus, s))
  b = F.part(b, 3, s => S.blit_rgba(s, 3, 200.0, 40.0, 64, 64, picture(64, 64)))
  b = F.part(b, 4, s => S.fill_rect(s, G.Rect{x, 90.0, 120.0, 50.0}, 2164195456))
  b = F.part(b, 5, s => S.blit_mask(s, 1, F32.neg(30.0), 140.0, 100, 60, ramp(100, 60), 2868903935))
  F.end(F.part(big.part(bg, glyph.part(gl, extra.part(more, b))), 9, s => dots(4200n, 0n, s)))

def store.check(got: Gpu.Renderer & F.Frame, +before: U32) -> IO(Gpu.Renderer & F.Frame):
  (+r, f) = got
  do IO<Gpu.Renderer & F.Frame>:
    check(U32.is_gt(V.store_generation(Gpu.gpu(r)), before), "store: that frame started the store over (" ++
      U32.show(V.stored(Gpu.gpu(r))) ++ " quads stored)")
    return (r, f)

# A part with more new quads than the store has room for: the store starts
# over inside the frame, and every part the frame draws is planned again.
def store.step(prev: Gpu.Renderer & F.Frame, l: Setup) -> IO(Gpu.Renderer & F.Frame):
  (+r, last) = prev
  +before = V.store_generation(Gpu.gpu(r))
  +next = dotted(l, last)
  +damaged = F.area(F.regions(next), 0)
  do IO<Gpu.Renderer & F.Frame>:
    check(Bool.not(F.whole(next)) && U32.is_gt(damaged, 0) && U32.is_lt(damaged, 32000),
      "frames: a part with more quads than the store has room for: drawn partly, " ++ U32.show(damaged) ++
      " of 64000 pixels damaged")
    got : Gpu.Renderer & F.Frame <- rendered(r, next, 320, 200,
      "frames: a part with more quads than the store has room for, so the store starts over inside the frame")
    store.check(got, before)

def back(prev: Gpu.Renderer & F.Frame) -> IO(Gpu.Renderer & F.Frame):
  (+r, last) = prev
  do IO<Gpu.Renderer & F.Frame>:
    +r1 : Gpu.Renderer <- Gpu.resize(r, 320, 200)
    rendered(r1, framed(setup(), last), 320, 200, "frames: back at 320x200, whole")

def frames(+r0: Gpu.Renderer) -> IO(Gpu.Renderer):
  do IO<Gpu.Renderer>:
    s1 : Gpu.Renderer & F.Frame <- rendered(r0, framed(setup(), F.none()), 320, 200,
      "frames: the first frame, drawn whole")
    s2 : Gpu.Renderer & F.Frame <- step(s1, with_hover(setup()), "frames: hover, under a translucent part")
    s3 : Gpu.Renderer & F.Frame <- step(s2, with_focus(with_hover(setup())), "frames: focus ring added")
    s4 : Gpu.Renderer & F.Frame <- step(s3, moved(with_focus(with_hover(setup()))),
      "frames: a translucent part moved across others")
    s5 : Gpu.Renderer & F.Frame <- step(s4, added(moved(with_focus(with_hover(setup())))),
      "frames: a part added")
    s5b : Gpu.Renderer & F.Frame <- step(s5, with_glyph(added(moved(with_focus(with_hover(setup()))))),
      "frames: a glyph the atlas has not seen, uploaded inside the frame")
    s5c : Gpu.Renderer & F.Frame <- step.reset(s5b, with_big(with_glyph(added(moved(with_focus(with_hover(setup())))))),
      "frames: a mask that does not fit, so the atlas starts over inside the frame")
    s5d : Gpu.Renderer & F.Frame <- step(s5c,
      without_hover(with_big(with_glyph(added(moved(with_focus(with_hover(setup()))))))),
      "frames: after the atlas started over, kept parts are planned again where drawn")
    s5e : Gpu.Renderer & F.Frame <- store.step(s5d,
      without_hover(with_big(with_glyph(added(moved(with_focus(with_hover(setup()))))))))
    s6 : Gpu.Renderer & F.Frame <- resized.step(s5e)
    s7 : Gpu.Renderer & F.Frame <- back(s6)
    stripped(s7)

# Running
# -------

def frame.compared(got: Gpu.Renderer & Array<U32>, +s: S.Scene, name: String) -> IO(Gpu.Renderer):
  (r, px) = got
  do IO<Gpu.Renderer>:
    compared(px, R.pixels(s), name)
    return r

def frame(+r: Gpu.Renderer, +s: S.Scene, name: String) -> IO(Gpu.Renderer):
  do IO<Gpu.Renderer>:
    +r1 : Gpu.Renderer <- Gpu.draw(r, s)
    got : Gpu.Renderer & Array<U32> <- Gpu.read(r1)
    frame.compared(got, s, name)

# A control: the comparison must notice a different scene.
def control.compared(got: Gpu.Renderer & Array<U32>) -> IO(Gpu.Renderer):
  (r, px) = got
  +total = (width() * height() : U32)
  do IO<Gpu.Renderer>:
    control.verdict(compare.ref(px, R.pixels(rounded())), total)
    return r

def run(+r0: Gpu.Renderer) -> IO(Gpu.Renderer):
  do IO<Gpu.Renderer>:
    +r1 : Gpu.Renderer <- frame(r0, shapes(), "fills, borders, clips, translucency, fractional and negative edges")
    +r2 : Gpu.Renderer <- frame(r1, rounded(), "rounded boxes and borders, fractional, clipped, overlapping")
    +r3 : Gpu.Renderer <- frame(r2, textures(), "coverage masks and RGBA bitmaps through the atlas, clipped, off the surface")
    +before : U32 = Gpu.uploaded(r3)
    +r4 : Gpu.Renderer <- frame(r3, mixed(), "a mixed UI frame")
    check(U32.is_eq(Gpu.uploaded(r4), before) && U32.is_eq(Gpu.entries(r4), 4) && U32.is_eq(Gpu.resets(r4), 0),
      "atlas: keys seen before are reused, nothing uploaded again (" ++ U32.show(Gpu.entries(r4)) ++
      " entries, " ++ U32.show(Gpu.uploaded(r4)) ++ " texels uploaded in total)")
    +r5 : Gpu.Renderer <- Gpu.draw(r4, shapes())
    got : Gpu.Renderer & Array<U32> <- Gpu.read(r5)
    control.compared(got)

def ops_of(r: Result<&1, &1, U32 & String, List<&2, S.Op>>) -> List<&2, S.Op>:
  match r:
    case Fail{e}:
      Nil{}
    case Done{os}:
      os

# Planning against a 64x64 atlas: the 100x60 mask cannot fit.
def overflow() -> Bool:
  Gpu.full(Gpu.plan(ops_of(S.ops(textures())), At.new(64, 64)))

def fits() -> Bool:
  Bool.not(Gpu.full(Gpu.plan(ops_of(S.ops(shapes())), At.new(64, 64))))

def finished(+r: Gpu.Renderer) -> IO(Unit):
  do IO<Unit>:
    +report : V.Report <- Gpu.close(r)
    IO.print(V.report.show(report))

def main() -> IO(Unit):
  do IO<Unit>:
    +r : Gpu.Renderer <- Gpu.open_offscreen(width(), height())
    IO.print(V.describe(Gpu.gpu(r)))
    +r1 : Gpu.Renderer <- run(r)
    +r2 : Gpu.Renderer <- frames(r1)
    check(overflow() && fits(), "atlas: a frame that does not fit is detected (the renderer then starts the atlas over)")
    finished(r2)
