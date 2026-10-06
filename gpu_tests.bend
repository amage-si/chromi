import Base
import ./geometry.bend as G
import ./scene.bend as S
import ./replay.bend as R
import ./gpu.bend as Gpu
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
    check(overflow() && fits(), "atlas: a frame that does not fit is detected (the renderer then starts the atlas over)")
    finished(r1)
