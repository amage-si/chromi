import Base
import ../../scene.bend as S
import ../../frame.bend as Fr
import ../../gpu.bend as Gpu
import ../../geometry.bend as G
import ./ui.bend as U
import ./text.bend as T
import ../../../Runika/font.bend as F
import ../../../Ankra/window.bend as A
import ../../../Ankra/app.bend as Loop
import ../../../Kairo/ankra_adapter.bend as AA
import ../../../Kairo/main.bend as K
import ../../../Kairo/types.bend as KT
import ../../../Tessra/geometry.bend as TG
import ../../../Mokko/main.bend as M
import ../../../Voltra/gpu.bend as V

# A text-heavy scene for benchmarks: the demo's Mokko button and an
# activation counter above N labels ("0001".."N", 10 px) in a grid of 31
# columns of 28x12 cells from (16, 64). It runs on the same path as the
# integrated demo (Ankra window, Kairo, Chromi retained frame, Voltra) and
# logs the same way. Each label's text run is prepared once at startup; an
# activation (Tab, then Space or Enter, or a click) re-prepares only the
# counter. The frame has three parts: the button (keyed by its Kairo id),
# the counter and the labels; the labels are recorded once per window size
# (a stamped part), and labels outside the window are not painted at all,
# so an activation redraws the button and the counter only.
#
#   ./build/grid [N] --threads 2 --gpu off      (N defaults to 1000)
#
# The bench repository (amage-si/eco-bench) compares it with GPUI.

def font_path() -> String:
  "/usr/share/fonts/liberation/LiberationSans-Regular.ttf"

def columns() -> U32:
  31

def need(-A: Data, r: Result<&2, &2, String, A>) -> IO(A):
  match r:
    case Fail{message}:
      IO.die(A, 1, message)
    case Done{x}:
      IO.pure(A, x)

# Model
# -----

# A label's run and its top-left corner.
type Cell is Data:
  Cell{x: F32, y: F32, run: T.Run}

type Grid is Data:
  Grid{font: F.Font, cache: T.Cache, label: T.Run, counter: T.Run, cells: List<&2, Cell>,
    kairo: KT.State, clicks: U32, width: U32, height: U32}

def run_of(p: T.Prepared) -> T.Run:
  T.Prepared{r, c} = p
  r

def cache_of(p: T.Prepared) -> T.Cache:
  T.Prepared{r, c} = p
  c

# "0042" for 42.
def pad4(+n: U32) -> String:
  +s = U32.show(n)
  Bool.pick(String, U32.is_lt(n, 10), "000" ++ s,
    Bool.pick(String, U32.is_lt(n, 100), "00" ++ s, Bool.pick(String, U32.is_lt(n, 1000), "0" ++ s, s)))

def counter_text(+n: U32) -> String:
  "Ativações: " ++ U32.show(n)

def cell_x(+i: U32) -> F32:
  (16.0 + U32.to_f32((i % columns() : U32)) * 28.0 : F32)

def cell_y(+i: U32) -> F32:
  (64.0 + U32.to_f32((i / columns() : U32)) * 12.0 : F32)

type Cells is Data:
  Cells{cells: List<&2, Cell>, cache: T.Cache}

# Labels i .. i + n - 1 (0-based), prepared with the shared glyph cache.
def cells.go(n: Nat, +i: U32, +font: F.Font, +cache: T.Cache, acc: List<&2, Cell>) ->
  Result<&2, &2, String, Cells>:
  match n:
    case 0n:
      Done{Cells{List.reverse(&2, Cell, acc), cache}}
    case 1n+p:
      do Result<&2, &2, String, Cells>:
        +prepared : T.Prepared <- T.prepare(font, pad4((i + 1 : U32)), 10.0, 1000000.0, cache)
        cells.go(p, (i + 1 : U32), font, cache_of(prepared), Cell{cell_x(i), cell_y(i), run_of(prepared)} <> acc)

def label_size(+run: T.Run) -> TG.Size:
  M.button_size(U.metrics(run))

def rect_at(s: TG.Size) -> TG.Rect:
  TG.Size{bw, bh} = s
  TG.Rect{16.0, 8.0, bw, bh}

def button_rect(+run: T.Run) -> TG.Rect:
  rect_at(label_size(run))

def built(+font: F.Font, label: T.Prepared, counter: T.Prepared, cs: Cells, +k: KT.State, +w: U32, +h: U32) -> Grid:
  Cells{cells, cache} = cs
  Grid{font, cache, run_of(label), run_of(counter), cells, k, 0, w, h}

def build(+font: F.Font, +n: U32, +w: U32, +h: U32) -> Result<&2, &2, String, Grid>:
  do Result<&2, &2, String, Grid>:
    +label : T.Prepared <- T.prepare(font, U.label(), 18.0, 1000000.0, T.cache())
    +counter : T.Prepared <- T.prepare(font, counter_text(0), 16.0, 1000000.0, cache_of(label))
    +cs : Cells <- cells.go(U32.to_nat(n), 0, font, cache_of(counter), Nil{})
    +k : KT.State <- U.started(K.init([U.button_node(button_rect(run_of(label)))], U32.to_f32(w), U32.to_f32(h)))
    return built(font, label, counter, cs, k, w, h)

def recount.made(m: Grid, p: T.Prepared, +clicks: U32, +w: U32, +h: U32) -> Grid:
  Grid{f, old, l, c, cells, k, n, ow, oh} = m
  T.Prepared{run, cache} = p
  Grid{f, cache, l, run, cells, k, clicks, w, h}

def resized_model(m: Grid, +w: U32, +h: U32) -> Grid:
  Grid{f, cache, l, c, cells, k, n, ow, oh} = m
  Grid{f, cache, l, c, cells, k, n, w, h}

def font_of(m: Grid) -> F.Font:
  Grid{f, cache, l, c, cells, k, n, w, h} = m
  f

def glyph_cache(m: Grid) -> T.Cache:
  Grid{f, cache, l, c, cells, k, n, w, h} = m
  cache

# A new click count re-prepares the counter only; a new size only changes
# the frame's size (the grid does not depend on it).
def recount(again: Bool, +m: Grid, +clicks: U32, +w: U32, +h: U32) -> Result<&2, &2, String, Grid>:
  match again:
    case False{}:
      Done{resized_model(m, w, h)}
    case True{}:
      do Result<&2, &2, String, Grid>:
        +p : T.Prepared <- T.prepare(font_of(m), counter_text(clicks), 16.0, 1000000.0, glyph_cache(m))
        return recount.made(m, p, clicks, w, h)

def kairo(m: Grid) -> KT.State:
  Grid{f, cache, l, c, cells, k, n, w, h} = m
  k

def with_kairo(m: Grid, +k: KT.State) -> Grid:
  Grid{f, cache, l, c, cells, old, n, w, h} = m
  Grid{f, cache, l, c, cells, k, n, w, h}

def clicks(m: Grid) -> U32:
  Grid{f, cache, l, c, cells, k, n, w, h} = m
  n

def size_of(m: Grid) -> U32 & U32:
  Grid{f, cache, l, c, cells, k, n, w, h} = m
  (w, h)

def glyphs(m: Grid) -> U32:
  Grid{f, cache, l, c, cells, k, n, w, h} = m
  T.glyph_count(cache)

# The frame
# ---------

def paint_cell(seen: Bool, s: S.Scene, run: T.Run, +x: F32, +y: F32) -> S.Scene:
  match seen:
    case True{}:
      T.paint(s, run, x, y, U.muted())
    case False{}:
      s

# Labels whose box (with a margin for glyphs past the run's line box)
# cannot show are skipped before any glyph is placed.
def paint_cells(cs: List<&2, Cell>, +s: S.Scene) -> S.Scene:
  match cs:
    case Nil{}:
      s
    case Con{Cell{+x, +y, +run}, rest}:
      paint_cells(rest, paint_cell(S.visible(s, G.Rect{(x - 4.0 : F32), (y - 4.0 : F32),
        (T.width(run) + 8.0 : F32), (T.height(run) + 8.0 : F32)}), s, run, x, y))

# The counter 16 px right of the button, centered on it vertically.
def paint_counter(s: S.Scene, size: TG.Size, +counter: T.Run) -> S.Scene:
  TG.Size{bw, bh} = size
  T.paint(s, counter, (32.0 + bw : F32), (8.0 + (bh - T.height(counter)) / 2.0 : F32), U.ink())

def counter_id() -> U32:
  2

def cells_id() -> U32:
  3

# The next frame after `last`: the button (Kairo's id) and the counter are
# recorded and compared every frame; the labels only for a new window size.
def frame(m: Grid, last: Fr.Frame) -> Fr.Frame:
  Grid{f, cache, +label, counter, cells, k, n, +w, +h} = m
  b = Fr.begin(last, w, h, 1.0, U.background())
  b = Fr.part(b, U.button_id(), s => U.button(M.button(U.button_node(button_rect(label)), k,
    U.metrics(label), 18.0, M.theme()), s, label))
  b = Fr.part(b, counter_id(), s => paint_counter(s, label_size(label), counter))
  Fr.end(Fr.stamped(b, cells_id(), 1, s => paint_cells(cells, s)))

# Input (as in main.bend)
# -----------------------

type GridApp is Data:
  GridApp{renderer: Gpu.Renderer, model: Grid, shown: Fr.Frame, redraws: U32, started: Nat}

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

def resized(again: Bool, +r: Gpu.Renderer, +w: U32, +h: U32) -> IO(Gpu.Renderer):
  match again:
    case False{}:
      IO.pure(Gpu.Renderer, r)
    case True{}:
      Gpu.resize(r, w, h)

def differs(size: U32 & U32, +w: U32, +h: U32) -> Bool:
  (mw, mh) = size
  U32.is_ne(mw, w) || U32.is_ne(mh, h)

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
    case A.TextTyped{t}:
      " text \"" ++ t ++ "\""
    case A.Clipboard{c}:
      " clipboard"

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

def decide(+app: GridApp, +redraw: Bool) -> Loop.Step<GridApp>:
  Bool.pick(Loop.Step<GridApp>, redraw, Loop.Redraw{app}, Loop.Keep{app})

def update.folded(+win: A.Win, +es: List<&2, A.Input>, app: GridApp, f: Fold) -> IO(Loop.Step<GridApp>):
  GridApp{+r, +m, shown, n, t} = app
  Fold{+k, +a, +d} = f
  +w = A.width(win)
  +h = A.height(win)
  +sized = differs(size_of(m), w, h)
  do IO<Loop.Step<GridApp>>:
    logged(es, a)
    +r1 : Gpu.Renderer <- resized(sized, r, w, h)
    +m1 : Grid <- need(Grid, recount(U32.is_gt(a, 0), with_kairo(m, k), (clicks(m) + a : U32), w, h))
    return decide(GridApp{r1, m1, shown, n, t}, d || sized || U32.is_gt(a, 0) || A.exposed(es) || Gpu.pending(r1))

def model_of(a: GridApp) -> Grid:
  GridApp{r, m, s, n, t} = a
  m

def update(win: A.Win, batch: List<&2, A.Input>, state: GridApp) -> IO(Loop.Step<GridApp>):
  +es = batch
  +app = state
  do IO<Loop.Step<GridApp>>:
    +inputs : List<&2, KT.Input> <- need(List<&2, KT.Input>, AA.normalize(es, 1.0))
    update.folded(win, es, app, fold(inputs, Fold{kairo(model_of(app)), 0, False{}}))

# Drawing, startup and teardown (as in main.bend)
# -----------------------------------------------

def report(+n: U32, +ms: Nat, +r: Gpu.Renderer, +m: Grid, +since: Nat) -> IO(Unit):
  IO.print("redraw " ++ U32.show(n) ++ " at " ++ Nat.show(since) ++ " ms: scene + GPU " ++ Nat.show(ms) ++
    " ms, " ++ Bool.pick(String, Gpu.last_partial(r), "damage only, ", "whole, ") ++
    U32.show(Gpu.last_quads(r)) ++ " quads, " ++ U32.show(glyphs(m)) ++ " glyphs cached, atlas " ++
    U32.show(Gpu.entries(r)) ++ " entries, " ++ U32.show(Gpu.uploaded(r)) ++ " texels uploaded")

def drawn(got: Gpu.Renderer & Fr.Frame, +m: Grid, +n: U32, +t: Nat, +t0: Nat) -> IO(Loop.Step<GridApp>):
  (+r1, shown) = got
  do IO<Loop.Step<GridApp>>:
    +t1 : Nat <- IO.now()
    report((n + 1 : U32), Nat.sub(t1, t0), r1, m, Nat.sub(t1, t))
    return decide(GridApp{r1, m, shown, (n + 1 : U32), t}, Gpu.pending(r1))

def draw(win: A.Win, app: GridApp) -> IO(Loop.Step<GridApp>):
  GridApp{+r, +m, last, +n, +t} = app
  do IO<Loop.Step<GridApp>>:
    +t0 : Nat <- IO.now()
    got : Gpu.Renderer & Fr.Frame <- Gpu.render(r, frame(m, last))
    drawn(got, m, n, t, t0)

def finish(end: A.Win & GridApp) -> IO(Unit):
  (win, app) = end
  GridApp{+r, +m, s, +n, t} = app
  do IO<Unit>:
    IO.print("frames presented: " ++ U32.show(V.drawn(Gpu.gpu(r))) ++ ", redraws: " ++ U32.show(n) ++
      ", clicks: " ++ U32.show(clicks(m)))
    +report : V.Report <- Gpu.close(r)
    IO.print(V.report.show(report))
    +left : U32 <- A.close(win)
    IO.print("window objects left: " ++ U32.show(left))

def count(args: List<String>, +n: U32) -> U32:
  match args:
    case Nil{}:
      n
    case Con{a, rest}:
      count(rest, Maybe.default(&2, U32, U32.read(a), n))

def title(+n: U32) -> String:
  "AMAGE Eco - grid " ++ U32.show(n)

def main() -> IO(Unit):
  do IO<Unit>:
    +t0 : Nat <- IO.now()
    args : List<String> <- IO.args()
    +n : U32 = count(args, 1000)
    loaded : Result<&2, &2, String, F.Font> <- F.load(font_path())
    +font : F.Font <- need(F.Font, loaded)
    +model : Grid <- need(Grid, build(font, n, 900, 560))
    +t1 : Nat <- IO.now()
    IO.print("assets ready in " ++ Nat.show(Nat.sub(t1, t0)) ++ " ms: font, " ++ U32.show(n) ++ " labels, " ++
      U32.show(glyphs(model)) ++ " glyphs")
    +win : A.Win <- IO.try(A.Win, A.open(A.options(title(n), 900, 560)))
    +native : List<&2, U32> <- A.native(win)
    +r : Gpu.Renderer <- Gpu.open(native, 900, 560, True{})
    +t2 : Nat <- IO.now()
    IO.print(V.describe(Gpu.gpu(r)))
    IO.print("window and GPU ready in " ++ Nat.show(Nat.sub(t2, t1)) ++ " ms")
    end : A.Win & GridApp <- Loop.run(~GridApp, ~update, ~draw, win, GridApp{r, model, Fr.none(), 0, t0})
    finish(end)
