import Base
import ../../scene.bend as S
import ../../frame.bend as Fr
import ../../gpu.bend as Gpu
import ./ui.bend as U
import ./media.bend as Media
import ../../../Runika/font.bend as F
import ../../../Ankra/window.bend as A
import ../../../Ankra/app.bend as Loop
import ../../../Ankra/clipboard.bend as Clip
import ../../../Kairo/ankra_adapter.bend as AA
import ../../../Kairo/main.bend as K
import ../../../Kairo/types.bend as KT
import ../../../Kairo/edit.bend as KE
import ../../../Mokko/field.bend as FL
import ../../../Tessra/geometry.bend as TG
import ../../../Voltra/gpu.bend as V

# The integrated demo, GPU-presented: Ankra owns the window and its
# events, the text input and the clipboard, Kairo the interaction state
# and the editing, Tessra the layout, Runika, Syllo and Dithra the text,
# Ocula the PNG, Splina the SVG, Mokko the button and the text field,
# Chromi the frame as a draw list, and Voltra draws that list on the GPU.
#
# The frame is redrawn only when something visible changed (hover, press,
# focus, a click, an edit, a new size, an expose); between changes the
# program waits for events without a deadline. An edit redraws only the
# field and its note. Resize the window: the layout
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
  Demo{renderer: Gpu.Renderer, model: U.Model, shown: Fr.Frame, redraws: U32, started: Nat, clip: Clip.Clip}

def need(-A: Data, r: Result<&2, &2, String, A>) -> IO(A):
  match r:
    case Fail{message}:
      IO.die(A, 1, message)
    case Done{x}:
      IO.pure(A, x)

# Input
# -----

# The field after Kairo's actions: `edited` when it must be drawn again,
# and the requests (copy, paste) for the host, newest first.
type Edits is Data:
  Edits{field: FL.Field, edited: Bool, requests: List<&2, KE.Request>}

def request.push(r: KE.Request, rs: List<&2, KE.Request>) -> List<&2, KE.Request>:
  match r:
    case KE.NoRequest{}:
      rs
    case KE.CopyText{t}:
      Con{KE.CopyText{t}, rs}
    case KE.PasteText{}:
      Con{KE.PasteText{}, rs}

def fed(x: FL.Fed, +edited: Bool, rs: List<&2, KE.Request>) -> Edits:
  FL.Fed{f, +d, r} = x
  Edits{f, edited || d, request.push(r, rs)}

# Every action of a Kairo change goes through the field, at its bounds.
def feed(actions: +List<KT.Action>, +font: F.Font, +at: TG.Rect, e: Edits) -> Edits:
  match actions:
    case Nil{}:
      e
    case Con{a, rest}:
      Edits{f, +ed, rs} = e
      feed(rest, font, at, fed(FL.feed(font, U.field_px(), at, U.field_id(), f, a), ed, rs))

type Fold is Data:
  Fold{kairo: KT.State, activations: U32, dirty: Bool, edits: Edits}

def changed(c: KT.Change) -> Bool:
  KT.Change{s, actions, dirty, layout} = c
  layout || Bool.not(U32.is_eq(U32.from_nat(List.length(&2, TG.Rect, dirty)), 0))

def activated(c: KT.Change) -> U32:
  KT.Change{s, actions, dirty, layout} = c
  K.activation_count(actions)

def actions_of(c: KT.Change) -> +List<KT.Action>:
  KT.Change{s, actions, dirty, layout} = c
  actions

def fold(xs: List<&2, KT.Input>, +font: F.Font, +at: TG.Rect, f: Fold) -> Fold:
  match xs:
    case Nil{}:
      f
    case Con{x, rest}:
      Fold{k, +a, +d, e} = f
      +c = K.dispatch(k, x)
      fold(rest, font, at, Fold{K.next(c), (a + activated(c) : U32), d || changed(c),
        feed(actions_of(c), font, at, e)})

# The clipboard's side of the edits: a copy takes the clipboard; a paste
# of our own clipboard is typed at once as Kairo text, a paste of another
# client's arrives in a later batch as Clipboard{Pasted} (Kairo's adapter
# makes it text).
type Served is Data:
  Served{clip: Clip.Clip, kairo: KT.State, edits: Edits}

def pasted(got: Maybe<&2, String>, +font: F.Font, +at: TG.Rect, s: Served) -> Served:
  match got:
    case None{}:
      s
    case Some{t}:
      Served{c, k, e} = s
      +ch = K.dispatch(k, KT.TextInput{t})
      Served{c, K.next(ch), feed(actions_of(ch), font, at, e)}

def owned_word(c: Clip.Clip) -> String:
  Bool.pick(String, Clip.owned(c), "owned", "not owned")

def paste_word(got: Maybe<&2, String>) -> String:
  match got:
    case None{}:
      "asked the owner"
    case Some{t}:
      "own text \"" ++ t ++ "\""

def requested(rs: List<&2, KE.Request>, +win: A.Win, +font: F.Font, +at: TG.Rect, s: Served) -> IO(Served):
  match rs:
    case Nil{}:
      IO.pure(Served, s)
    case Con{KE.CopyText{+t}, rest}:
      Served{c, k, e} = s
      do IO<Served>:
        +c1 : Clip.Clip <- Clip.copy(win, t)
        IO.print("clipboard: copy \"" ++ t ++ "\", " ++ owned_word(c1))
        requested(rest, win, font, at, Served{c1, k, e})
    case Con{KE.PasteText{}, rest}:
      Served{+c, k, e} = s
      do IO<Served>:
        +got : Maybe<&2, String> <- Clip.paste(win, c)
        IO.print("clipboard: paste, " ++ paste_word(got))
        requested(rest, win, font, at, pasted(got, font, at, Served{c, k, e}))
    case Con{KE.NoRequest{}, rest}:
      requested(rest, win, font, at, s)

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
    case A.TextTyped{t}:
      " text \"" ++ t ++ "\""
    case A.Clipboard{A.Asked{A.Request{q, p, target, tm, atom}}}:
      " clipboard-asked " ++ U32.show(target)
    case A.Clipboard{A.Lost{}}:
      " clipboard-lost"
    case A.Clipboard{A.Pasted{t}}:
      " pasted \"" ++ t ++ "\""
    case A.Clipboard{A.PasteFailed{code}}:
      " paste-failed " ++ U32.show(code)

def words(es: List<&2, A.Input>) -> String:
  match es:
    case Nil{}:
      ""
    case Con{e, rest}:
      word(e) ++ words(rest)

# What the field became, after the batch's input.
def refusal_word(m: Maybe<&2, String>) -> String:
  match m:
    case None{}:
      ""
    case Some{message}:
      " refused: " ++ message

def field_word(edited: Bool, +f: FL.Field) -> String:
  match edited:
    case False{}:
      ""
    case True{}:
      " -> field \"" ++ FL.text_of(f) ++ "\"" ++ refusal_word(FL.message(f))

def logged(+es: List<&2, A.Input>, +at: Nat, +activations: U32, tail: String) -> IO(Unit):
  match es:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case _:
      IO.print("input at " ++ Nat.show(at) ++ " ms:" ++ words(es) ++ Bool.pick(String, U32.is_gt(activations, 0),
        " -> " ++ U32.show(activations) ++ " activation(s)", "") ++ tail)

def decide(+app: Demo, +redraw: Bool) -> Loop.Step<Demo>:
  Bool.pick(Loop.Step<Demo>, redraw, Loop.Redraw{app}, Loop.Keep{app})

def refielded(edited: Bool, +m: U.Model, +f: FL.Field) -> IO(U.Model):
  match edited:
    case False{}:
      IO.pure(U.Model, m)
    case True{}:
      relaid(U.refield(m, f))

def update.served(+win: A.Win, +es: List<&2, A.Input>, app: Demo, +a: U32, +d: Bool, +now: Nat, s: Served) -> IO(Loop.Step<Demo>):
  Demo{+r, +m, shown, n, +t, old} = app
  Served{clip, +k, Edits{+field, +edited, rs}} = s
  +w = A.width(win)
  +h = A.height(win)
  +sized = other_size(m, w, h)
  +again = sized || U32.is_gt(a, 0)
  do IO<Loop.Step<Demo>>:
    logged(es, Nat.sub(now, t), a, field_word(edited, field))
    +r1 : Gpu.Renderer <- resized(sized, r, w, h)
    +m1 : U.Model <- refielded(edited, U.with_kairo(m, k), field)
    +m2 : U.Model <- remodel(again, m1, w, h, (U.clicks(m) + a : U32))
    return decide(Demo{r1, m2, shown, n, t, clip}, d || edited || again || A.exposed(es) || Gpu.pending(r1))

# Kairo's actions reach the field; the clipboard answers other clients
# (serve) and the field's requests (copy, paste).
# Small views of the app. The Demo is wide (the model is flattened into
# it), so no def holds the Demo and its model at once.
def model_of(a: Demo) -> U.Model:
  Demo{r, m, s, n, t, c} = a
  m

def clip_of(a: Demo) -> Clip.Clip:
  Demo{r, m, s, n, t, c} = a
  c

def font_of(a: Demo) -> F.Font:
  Demo{r, m, s, n, t, c} = a
  U.font_of(m)

def field_at(a: Demo) -> TG.Rect:
  Demo{r, m, s, n, t, c} = a
  U.field_at(m)

def started_fold(a: Demo) -> Fold:
  Demo{r, +m, s, n, t, c} = a
  Fold{U.kairo(m), 0, False{}, Edits{U.field_of(m), False{}, Nil{}}}

def update.folded(+win: A.Win, +es: List<&2, A.Input>, +app: Demo, +now: Nat, f: Fold) -> IO(Loop.Step<Demo>):
  Fold{k, +a, +d, Edits{field, edited, rs}} = f
  do IO<Loop.Step<Demo>>:
    +c1 : Clip.Clip <- Clip.serve(win, clip_of(app), es)
    +s : Served <- requested(List.reverse(&2, KE.Request, rs), win, font_of(app), field_at(app),
      Served{c1, k, Edits{field, edited, Nil{}}})
    update.served(win, es, app, a, d, now, s)

# Window events through Kairo and the field; a new size or a click redoes
# the layout, an edit the field's text and note.
def update(win: A.Win, batch: List<&2, A.Input>, state: Demo) -> IO(Loop.Step<Demo>):
  +es = batch
  +app = state
  do IO<Loop.Step<Demo>>:
    +now : Nat <- IO.now()
    +inputs : List<&2, KT.Input> <- need(List<&2, KT.Input>, AA.normalize(es, 1.0))
    update.folded(win, es, app, now, fold(inputs, font_of(app), field_at(app), started_fold(app)))

# Drawing
# -------

def report(+n: U32, +ms: Nat, +r: Gpu.Renderer, +m: U.Model, +since: Nat, +damage: U32) -> IO(Unit):
  IO.print("redraw " ++ U32.show(n) ++ " at " ++ Nat.show(since) ++ " ms: scene + GPU " ++ Nat.show(ms) ++
    " ms, " ++ Bool.pick(String, Gpu.last_partial(r), "damage only (" ++ U32.show(damage) ++ " px), ", "whole, ") ++
    U32.show(Gpu.last_quads(r)) ++ " quads, " ++ U32.show(U.glyphs(m)) ++ " glyphs cached, atlas " ++
    U32.show(Gpu.entries(r)) ++ " entries, " ++ U32.show(Gpu.uploaded(r)) ++ " texels uploaded")

def drawn(got: Gpu.Renderer & Fr.Frame, +m: U.Model, +n: U32, +t: Nat, +t0: Nat, +damage: U32, clip: Clip.Clip) -> IO(Loop.Step<Demo>):
  (+r1, shown) = got
  do IO<Loop.Step<Demo>>:
    +t1 : Nat <- IO.now()
    report((n + 1 : U32), Nat.sub(t1, t0), r1, m, Nat.sub(t1, t), damage)
    return decide(Demo{r1, m, shown, (n + 1 : U32), t, clip}, Gpu.pending(r1))

# The frame is retained (Chromi's frame.bend): only what changed since the
# last one is planned and redrawn. The report gives the damaged area in
# pixels (the regions a partial frame redraws).
def draw(win: A.Win, app: Demo) -> IO(Loop.Step<Demo>):
  Demo{+r, +m, last, +n, +t, clip} = app
  do IO<Loop.Step<Demo>>:
    +t0 : Nat <- IO.now()
    +f : Fr.Frame <- IO.pure(Fr.Frame, U.framed(m, last))
    got : Gpu.Renderer & Fr.Frame <- Gpu.render(r, f)
    drawn(got, m, n, t, t0, Fr.area(Fr.regions(f), 0), clip)

# Startup and teardown
# --------------------

def finish(end: A.Win & Demo) -> IO(Unit):
  (win, app) = end
  Demo{+r, +m, s, +n, t, c} = app
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
    end : A.Win & Demo <- Loop.run(~Demo, ~update, ~draw, win, Demo{r, model, Fr.none(), 0, t0, Clip.none()})
    finish(end)
