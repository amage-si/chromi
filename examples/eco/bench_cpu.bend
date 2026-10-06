import Base
import ../../scene.bend as S
import ../../replay.bend as R
import ./ui.bend as U
import ./media.bend as Media
import ../../../Runika/font.bend as F
import ../../../Ankra/main.bend as A
import ../../../Kairo/main.bend as K
import ../../../Kairo/types.bend as KT
import ../../../Voltra/bench/cpu.bend as Cpu

# The demo scene redrawn N times through the previous path: Chromi paints
# the draw list on the CPU (replay.bend: the quadtree canvas), and the
# official runtime window (Ankra's main.bend) presents each image with
# XPutImage at its 60 Hz pacing, in a fixed 900x560 window. Every frame
# the pointer moves on or off the button, exactly as eco/bench_gpu.bend
# does. A number argument sets N (default 300). CPU time is the whole
# process's from /proc/self/stat; startup and the first frame are
# excluded. Run from the Chromi directory.

type Host is Data:
  Host{model: U.Model, frame: U32, frames: U32, started: Nat, ticks: U32, t0: Nat}

def need(-A: Data, r: Result<&2, &2, String, A>) -> IO(A):
  match r:
    case Fail{message}:
      IO.die(A, 1, message)
    case Done{x}:
      IO.pure(A, x)

def hover(+m: U.Model, +on: Bool) -> U.Model:
  +x = Bool.pick(F32, on, 95.0, 600.0)
  U.with_kairo(m, K.next(K.dispatch(U.kairo(m), KT.PointerMove{x, 218.0})))

def paint(+m: U.Model) -> IO(Image):
  IO.try(Image, IO.pure(Result<&1, &1, U32 & String, Image>, R.image(U.frame(m))))

def next(+m: U.Model, +i: U32, +n: U32, +t1: Nat, +c1: U32, +t0: Nat) -> IO(A.Step<Host>):
  +m1 = hover(m, U32.is_eq((i % 2 : U32), 0))
  do IO<A.Step<Host>>:
    image : Image <- paint(m1)
    return A.Redraw{Host{m1, (i + 1 : U32), n, t1, c1, t0}, image}

def report(+n: U32, +t1: Nat, +c1: U32) -> IO(A.Step<Host>):
  do IO<A.Step<Host>>:
    +t2 : Nat <- IO.now()
    +c2 : U32 <- Cpu.ticks()
    IO.print("cpu XPutImage: " ++ U32.show(n) ++ " redraws in " ++ Nat.show(Nat.sub(t2, t1)) ++ " ms (" ++
      U32.show((U32.from_nat(Nat.sub(t2, t1)) * 1000 / n : U32)) ++ " us/frame), " ++
      U32.show((c2 - c1 : U32)) ++ " CPU ticks, " ++ Cpu.per_frame((c2 - c1 : U32), n))
    return A.Stop{}

def step(first: Bool, last: Bool, +m: U.Model, +i: U32, +n: U32, +t1: Nat, +c1: U32, +t0: Nat) -> IO(A.Step<Host>):
  match first last:
    case True{} _:
      do IO<A.Step<Host>>:
        +t : Nat <- IO.now()
        +c : U32 <- Cpu.ticks()
        IO.print("first frame presented " ++ Nat.show(Nat.sub(t, t0)) ++ " ms after main started (mono " ++
          Nat.show(t) ++ ")")
        next(m, i, n, t, c, t0)
    case False{} True{}:
      report(n, t1, c1)
    case False{} False{}:
      next(m, i, n, t1, c1, t0)

# Each tick follows a presented frame: the first one starts the clock, the
# last one stops it.
def tick(batch: A.Batch, host: Host) -> IO(A.Step<Host>):
  Host{+m, +i, +n, +t1, +c1, +t0} = host
  step(U32.is_eq(i, 0), U32.is_eq(i, (n + 1 : U32)), m, i, n, t1, c1, t0)

def count(args: List<String>, +fallback: U32) -> U32:
  match args:
    case Nil{}:
      fallback
    case Con{a, rest}:
      +w = a
      count(rest, Maybe.default(&2, U32, U32.read(w), fallback))

def main() -> IO(Unit):
  do IO<Unit>:
    +t0 : Nat <- IO.now()
    args : List<String> <- IO.args()
    +n : U32 = count(args, 300)
    loaded : Result<&2, &2, String, F.Font> <- F.load("/usr/share/fonts/liberation/LiberationSans-Regular.ttf")
    +font : F.Font <- need(F.Font, loaded)
    +picture : Media.Picture <- Media.png("/usr/share/pixmaps/kitty.png")
    +heart : List<&2, Media.Shape> <- Media.svg("../Splina/fixtures/heart-fill.svg", U.heart_color(), 96.0)
    +model : U.Model <- need(U.Model, U.build(U.Assets{font, picture, heart}, 900, 560))
    image : Image <- paint(model)
    A.run(~Host, ~tick, "AMAGE Eco - CPU bench", 900, 560, 4294967295n, Host{model, 0, n, 0n, 0, t0}, image)
