import Base
import ../../scene.bend as S
import ../../gpu.bend as Gpu
import ./ui.bend as U
import ./media.bend as Media
import ../../../Runika/font.bend as F
import ../../../Ankra/window.bend as A
import ../../../Ankra/app.bend as Loop
import ../../../Kairo/ankra_adapter.bend as AA
import ../../../Kairo/main.bend as K
import ../../../Kairo/types.bend as KT
import ../../../Tessra/geometry.bend as TG
import ../../../Voltra/gpu.bend as V

# The integrated demo, GPU-presented: Ankra owns the window and its
# events, Kairo the interaction state, Tessra the layout, Runika, Syllo
# and Dithra the text, Ocula the PNG, Splina the SVG, Mokko the button,
# Chromi the frame as a draw list, and Voltra draws that list on the GPU.
#
# The frame is redrawn only when something visible changed (hover, press,
# focus, a click, a new size, an expose); between changes the program
# waits for events without a deadline. Resize the window: the layout
# follows. Close it normally. Run from the Chromi directory (the SVG path
# is relative; the PNG and the font are system files).

def font_path() -> String:
  "/usr/share/fonts/liberation/LiberationSans-Regular.ttf"

def png_path() -> String:
  "/usr/share/pixmaps/kitty.png"

def svg_path() -> String:
  "../Splina/fixtures/heart-fill.svg"

def title() -> String:
  "AMAGE Eco - Ankra, Voltra, Chromi"

type Demo is Data:
  Demo{renderer: Gpu.Renderer, model: U.Model, redraws: U32, started: Nat}

def need(-A: Data, r: Result<&2, &2, String, A>) -> IO(A):
  match r:
    case Fail{message}:
      IO.die(A, 1, message)
    case Done{x}:
      IO.pure(A, x)

# Input
# -----

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

type Next is Data:
  Next{model: U.Model, redraw: Bool}

def relaid(r: Result<&2, &2, String, U.Model>) -> IO(U.Model):
  need(U.Model, r)

def remodel(again: Bool, +m: U.Model, +w: U32, +h: U32, +clicks: U32) -> IO(U.Model):
  match again:
    case False{}:
      IO.pure(U.Model, m)
    case True{}:
      relaid(U.rebuild(m, w, h, clicks))

def resized(again: Bool, +r: Gpu.Renderer, +w: U32, +h: U32) -> IO(Gpu.Renderer):
  match again:
    case False{}:
      IO.pure(Gpu.Renderer, r)
    case True{}:
      Gpu.resize(r, w, h)

def differs(size: U32 & U32, +w: U32, +h: U32) -> Bool:
  (mw, mh) = size
  U32.is_ne(mw, w) || U32.is_ne(mh, h)

def other_size(+m: U.Model, +w: U32, +h: U32) -> Bool:
  differs(U.size_of(m), w, h)

# One line per batch of input, for the record: what arrived and what Kairo
# made of it.
def word(e: A.Input) -> String:
  match e:
    case A.Resized{w, h}:
      " resize " ++ U32.show(w) ++ "x" ++ U32.show(h)
    case A.Moved{x, y}:
      " moved"
    case A.Focused{g}:
      Bool.pick(String, g, " focus-in", " focus-out")
    case A.Exposed{}:
      " expose"
    case A.Shown{v}:
      Bool.pick(String, v, " mapped", " unmapped")
    case A.CloseRequested{}:
      " close"
    case A.KeyDown{c, r, m}:
      " key-down " ++ U32.show(c) ++ Bool.pick(String, r, "r", "")
    case A.KeyUp{c, m}:
      " key-up " ++ U32.show(c)
    case A.PointerMoved{x, y}:
      " move"
    case A.PointerDown{x, y, b, m}:
      " press " ++ U32.show(b)
    case A.PointerUp{x, y, b, m}:
      " release " ++ U32.show(b)
    case A.PointerEntered{x, y}:
      " enter"
    case A.PointerLeft{}:
      " leave"
    case A.Wheel{x, y, dx, dy}:
      " wheel"

def words(es: List<&2, A.Input>) -> String:
  match es:
    case Nil{}:
      ""
    case Con{e, rest}:
      word(e) ++ words(rest)

def logged(+es: List<&2, A.Input>, +activations: U32) -> IO(Unit):
  match es:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case _:
      IO.print("input:" ++ words(es) ++ Bool.pick(String, U32.is_gt(activations, 0),
        " -> " ++ U32.show(activations) ++ " activation(s)", ""))

def decide(+app: Demo, +redraw: Bool) -> Loop.Step<Demo>:
  Bool.pick(Loop.Step<Demo>, redraw, Loop.Redraw{app}, Loop.Keep{app})

def update.folded(+win: A.Win, +es: List<&2, A.Input>, app: Demo, f: Fold) -> IO(Loop.Step<Demo>):
  Demo{+r, +m, n, t} = app
  Fold{+k, +a, +d} = f
  +w = A.width(win)
  +h = A.height(win)
  +sized = other_size(m, w, h)
  +again = sized || U32.is_gt(a, 0)
  do IO<Loop.Step<Demo>>:
    logged(es, a)
    +r1 : Gpu.Renderer <- resized(sized, r, w, h)
    +m1 : U.Model <- remodel(again, U.with_kairo(m, k), w, h, (U.clicks(m) + a : U32))
    return decide(Demo{r1, m1, n, t}, d || again || A.exposed(es) || Gpu.pending(r1))

# Window events through Kairo; a new size or a click redoes the layout.
def model_of(a: Demo) -> U.Model:
  Demo{r, m, n, t} = a
  m

def update(win: A.Win, batch: List<&2, A.Input>, state: Demo) -> IO(Loop.Step<Demo>):
  +es = batch
  +app = state
  do IO<Loop.Step<Demo>>:
    +inputs : List<&2, KT.Input> <- need(List<&2, KT.Input>, AA.normalize(es, 1.0))
    update.folded(win, es, app, fold(inputs, Fold{U.kairo(model_of(app)), 0, False{}}))

# Drawing
# -------

def report(+n: U32, +ms: Nat, +r: Gpu.Renderer, +m: U.Model, +since: Nat) -> IO(Unit):
  +size = Gpu.target_size(r)
  IO.print("redraw " ++ U32.show(n) ++ " at " ++ Nat.show(since) ++ " ms: scene + GPU " ++ Nat.show(ms) ++
    " ms, " ++ U32.show(U.glyphs(m)) ++ " glyphs cached, atlas " ++ U32.show(Gpu.entries(r)) ++
    " entries, " ++ U32.show(Gpu.uploaded(r)) ++ " texels uploaded")

def draw(win: A.Win, app: Demo) -> IO(Loop.Step<Demo>):
  Demo{+r, +m, +n, +t} = app
  do IO<Loop.Step<Demo>>:
    +t0 : Nat <- IO.now()
    +r1 : Gpu.Renderer <- Gpu.draw(r, U.frame(m))
    +t1 : Nat <- IO.now()
    report((n + 1 : U32), Nat.sub(t1, t0), r1, m, Nat.sub(t1, t))
    return decide(Demo{r1, m, (n + 1 : U32), t}, Gpu.pending(r1))

# Startup and teardown
# --------------------

def finish(end: A.Win & Demo) -> IO(Unit):
  (win, app) = end
  Demo{+r, +m, +n, t} = app
  do IO<Unit>:
    IO.print("frames presented: " ++ U32.show(V.drawn(Gpu.gpu(r))) ++ ", redraws: " ++ U32.show(n) ++
      ", clicks: " ++ U32.show(U.clicks(m)))
    +report : V.Report <- Gpu.close(r)
    IO.print(V.report.show(report))
    +left : U32 <- A.close(win)
    IO.print("window objects left: " ++ U32.show(left))

def main() -> IO(Unit):
  do IO<Unit>:
    +t0 : Nat <- IO.now()
    loaded : Result<&2, &2, String, F.Font> <- F.load(font_path())
    +font : F.Font <- need(F.Font, loaded)
    +picture : Media.Picture <- Media.png(png_path())
    +heart : List<&2, Media.Shape> <- Media.svg(svg_path(), U.heart_color(), 96.0)
    +model : U.Model <- need(U.Model, U.build(U.Assets{font, picture, heart}, 900, 560))
    +t1 : Nat <- IO.now()
    IO.print("assets ready in " ++ Nat.show(Nat.sub(t1, t0)) ++ " ms: font, PNG (Ocula), SVG (Splina + Dithra), text, layout")
    +win : A.Win <- IO.try(A.Win, A.open(A.options(title(), 900, 560)))
    +native : List<&2, U32> <- A.native(win)
    +r : Gpu.Renderer <- Gpu.open(native, 900, 560, True{})
    +t2 : Nat <- IO.now()
    IO.print(V.describe(Gpu.gpu(r)))
    IO.print("window and GPU ready in " ++ Nat.show(Nat.sub(t2, t1)) ++ " ms")
    end : A.Win & Demo <- Loop.run(~Demo, ~update, ~draw, win, Demo{r, model, 0, t0})
    finish(end)
