import Base
import ../../scene.bend as S
import ../../replay.bend as R
import ./ui.bend as U
import ./media.bend as Media
import ../../../Runika/font.bend as F
import ../../../Ankra/main.bend as A
import ../../../Kairo/base_adapter.bend as B
import ../../../Kairo/main.bend as K
import ../../../Kairo/types.bend as KT
import ../../../Tessra/geometry.bend as TG

# The same demo scene on the previous path, for comparison: Chromi paints
# the draw list on the CPU (replay.bend), and the official runtime window
# (through Ankra's main.bend) presents it with XPutImage at a fixed
# 900x560, polling events once per frame at the runtime's 60 Hz pacing.
# Same model, layout, text, media and Kairo button as eco/main.bend; only
# the presentation differs. Run from the Chromi directory.

# `polls` counts the runtime's frame cycles: each one presents the retained
# image again and polls events (the official window has no idle wait).
type Host is Data:
  Host{model: U.Model, adapter: B.Adapter, redraws: U32, started: Nat, polls: U32}

def need(-A: Data, r: Result<&2, &2, String, A>) -> IO(A):
  match r:
    case Fail{message}:
      IO.die(A, 1, message)
    case Done{x}:
      IO.pure(A, x)

type Fold is Data:
  Fold{kairo: KT.State, activations: U32, dirty: Bool}

def changed(c: KT.Change) -> Bool:
  KT.Change{s, actions, dirty, layout} = c
  layout || Bool.not(U32.is_eq(U32.from_nat(List.length(&2, TG.Rect, dirty)), 0))

def activated(c: KT.Change) -> U32:
  KT.Change{s, actions, dirty, layout} = c
  K.activation_count(actions)

def fold(xs: List<&2, KT.Input>, f: Fold) -> Fold:
  match xs:
    case Nil{}:
      f
    case Con{x, rest}:
      Fold{k, +a, +d} = f
      +c = K.dispatch(k, x)
      fold(rest, Fold{K.next(c), (a + activated(c) : U32), d || changed(c)})

def remodel(again: Bool, +m: U.Model, +clicks: U32) -> IO(U.Model):
  match again:
    case False{}:
      IO.pure(U.Model, m)
    case True{}:
      need(U.Model, U.rebuild(m, 900, 560, clicks))

def paint(+m: U.Model) -> IO(Image):
  IO.try(Image, IO.pure(Result<&1, &1, U32 & String, Image>, R.image(U.frame(m))))

def redraw(go: Bool, +m: U.Model, adapter: B.Adapter, +n: U32, +t: Nat, +k: U32) -> IO(A.Step<Host>):
  match go:
    case False{}:
      IO.pure(A.Step<Host>, A.Keep{Host{m, adapter, n, t, k}})
    case True{}:
      do IO<A.Step<Host>>:
        +t0 : Nat <- IO.now()
        image : Image <- paint(m)
        +t1 : Nat <- IO.now()
        IO.print("redraw " ++ U32.show((n + 1 : U32)) ++ " at " ++ Nat.show(Nat.sub(t1, t)) ++
          " ms: CPU paint " ++ Nat.show(Nat.sub(t1, t0)) ++ " ms")
        return A.Redraw{Host{m, adapter, (n + 1 : U32), t, k}, image}

def folded(f: Fold, +m: U.Model, adapter: B.Adapter, +redraws: U32, +t: Nat, +polls: U32) -> IO(A.Step<Host>):
  Fold{+k, +a, +d} = f
  +again = U32.is_gt(a, 0)
  do IO<A.Step<Host>>:
    +m1 : U.Model <- remodel(again, U.with_kairo(m, k), (U.clicks(m) + a : U32))
    redraw(d || again, m1, adapter, redraws, t, polls)

def normalized(n: B.Normalized, +m: U.Model, +redraws: U32, +t: Nat, +polls: U32) -> IO(A.Step<Host>):
  B.Normalized{adapter, inputs} = n
  folded(fold(inputs, Fold{U.kairo(m), 0, False{}}), m, adapter, redraws, t, polls)

def polled.pick(due: Bool, +k: U32, +t: Nat) -> IO(Unit):
  match due:
    case True{}:
      do IO<Unit>:
        +now : Nat <- IO.now()
        IO.print("frame cycles: " ++ U32.show(k) ++ " at " ++ Nat.show(Nat.sub(now, t)) ++ " ms")
    case False{}:
      IO.pure(Unit, Unit{})

def polled(+k: U32, +t: Nat) -> IO(Unit):
  polled.pick(U32.is_eq((k % 600 : U32), 0), k, t)

def tick(batch: A.Batch, host: Host) -> IO(A.Step<Host>):
  A.Batch{closed, count, events} = batch
  Host{+m, adapter, +n, +t, +k} = host
  do IO<A.Step<Host>>:
    polled((k + 1 : U32), t)
    mapped : B.Normalized <- need(B.Normalized, B.normalize(events, adapter, 1.0))
    normalized(mapped, m, n, t, (k + 1 : U32))

def main() -> IO(Unit):
  do IO<Unit>:
    +t0 : Nat <- IO.now()
    loaded : Result<&2, &2, String, F.Font> <- F.load("/usr/share/fonts/liberation/LiberationSans-Regular.ttf")
    +font : F.Font <- need(F.Font, loaded)
    +picture : Media.Picture <- Media.png("/usr/share/pixmaps/kitty.png")
    +heart : List<&2, Media.Shape> <- Media.svg("../Splina/fixtures/heart-fill.svg", U.heart_color(), 96.0)
    +model : U.Model <- need(U.Model, U.build(U.Assets{font, picture, heart}, 900, 560))
    +t1 : Nat <- IO.now()
    image : Image <- paint(model)
    +t2 : Nat <- IO.now()
    IO.print("assets ready in " ++ Nat.show(Nat.sub(t1, t0)) ++ " ms; first CPU paint " ++
      Nat.show(Nat.sub(t2, t1)) ++ " ms")
    A.run(~Host, ~tick, "AMAGE Eco - CPU path", 900, 560, 4294967295n, Host{model, B.init(), 1, t0, 0}, image)
    IO.print("closed")
