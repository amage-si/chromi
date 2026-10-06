import Base
import ../../scene.bend as S
import ../../gpu.bend as Gpu
import ./ui.bend as U
import ./media.bend as Media
import ../../../Runika/font.bend as F
import ../../../Ankra/window.bend as A
import ../../../Kairo/main.bend as K
import ../../../Kairo/types.bend as KT
import ../../../Voltra/gpu.bend as V
import ../../../Voltra/bench/cpu.bend as Cpu

# The demo scene redrawn N times through the GPU path (Ankra window, Chromi
# draw list, Voltra), in a fixed 900x560 window. Every frame the pointer
# moves on or off the button, so Kairo changes the hover state and the
# whole frame is rebuilt and drawn, as an interactive redraw would. Events
# are polled once per frame. Arguments: `novsync` presents with IMMEDIATE
# instead of FIFO; a number sets N (default 300). CPU time is the whole
# process's (user + system, all threads) from /proc/self/stat; startup and
# the first frame (atlas upload) are excluded. Run from the Chromi
# directory. Pair with eco/bench_cpu.bend (the CPU/XPutImage path).

def need(-A: Data, r: Result<&2, &2, String, A>) -> IO(A):
  match r:
    case Fail{message}:
      IO.die(A, 1, message)
    case Done{x}:
      IO.pure(A, x)

# Pointer on the button (frame parity 0) or away from it.
def hover(+m: U.Model, +on: Bool) -> U.Model:
  +x = Bool.pick(F32, on, 95.0, 600.0)
  U.with_kairo(m, K.next(K.dispatch(U.kairo(m), KT.PointerMove{x, 218.0})))

def frames(n: Nat, +i: U32, +win: A.Win, +r: Gpu.Renderer, +m: U.Model) -> IO(Gpu.Renderer):
  match n:
    case 0n:
      IO.pure(Gpu.Renderer, r)
    case 1n+p:
      +m1 = hover(m, U32.is_eq((i % 2 : U32), 0))
      do IO<Gpu.Renderer>:
        +r1 : Gpu.Renderer <- Gpu.draw(r, U.frame(m1))
        got : A.Win & List<&2, A.Input> <- A.wait(win, 0)
        frames(p, (i + 1 : U32), win, r1, m1)

type Opts is Data:
  Opts{vsync: Bool, count: U32}

def opts(args: List<String>, +vsync: Bool, +count: U32) -> Opts:
  match args:
    case Nil{}:
      Opts{vsync, count}
    case Con{a, rest}:
      +w = a
      opts(rest, vsync && Bool.not(String.eq(w, "novsync")),
        Maybe.default(&2, U32, U32.read(w), count))

def run(+o: Opts, +font: F.Font, +picture: Media.Picture, +heart: List<&2, Media.Shape>, +t0: Nat) -> IO(Unit):
  Opts{+vsync, +n} = o
  do IO<Unit>:
    +model : U.Model <- need(U.Model, U.build(U.Assets{font, picture, heart}, 900, 560))
    +win : A.Win <- IO.try(A.Win, A.open(A.Options{"AMAGE Eco - GPU bench", 900, 560, False{}, 0, 0, "Ankra", 0}))
    +native : List<&2, U32> <- A.native(win)
    +r : Gpu.Renderer <- Gpu.open(native, 900, 560, vsync)
    +r1 : Gpu.Renderer <- Gpu.draw(r, U.frame(model))
    +t1 : Nat <- IO.now()
    IO.print("first frame presented " ++ Nat.show(Nat.sub(t1, t0)) ++ " ms after main started (mono " ++
      Nat.show(t1) ++ ")")
    +c1 : U32 <- Cpu.ticks()
    +r2 : Gpu.Renderer <- frames(U32.to_nat(n), 0, win, r1, model)
    +t2 : Nat <- IO.now()
    +c2 : U32 <- Cpu.ticks()
    IO.print("gpu " ++ Bool.pick(String, vsync, "FIFO", "IMMEDIATE") ++ ": " ++ U32.show(n) ++
      " redraws in " ++ Nat.show(Nat.sub(t2, t1)) ++ " ms (" ++
      U32.show((U32.from_nat(Nat.sub(t2, t1)) * 1000 / n : U32)) ++ " us/frame), " ++
      U32.show((c2 - c1 : U32)) ++ " CPU ticks, " ++ Cpu.per_frame((c2 - c1 : U32), n))
    +report : V.Report <- Gpu.close(r2)
    IO.print(V.report.show(report))
    +left : U32 <- A.close(win)
    IO.print("window objects left: " ++ U32.show(left))

def main() -> IO(Unit):
  do IO<Unit>:
    +t0 : Nat <- IO.now()
    args : List<String> <- IO.args()
    loaded : Result<&2, &2, String, F.Font> <- F.load("/usr/share/fonts/liberation/LiberationSans-Regular.ttf")
    +font : F.Font <- need(F.Font, loaded)
    +picture : Media.Picture <- Media.png("/usr/share/pixmaps/kitty.png")
    +heart : List<&2, Media.Shape> <- Media.svg("../Splina/fixtures/heart-fill.svg", U.heart_color(), 96.0)
    run(opts(args, True{}, 300), font, picture, heart, t0)
