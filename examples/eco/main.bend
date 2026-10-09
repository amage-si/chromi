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
import ../../../Mokko/anim.bend as MA
import ../../../Tessra/geometry.bend as TG
import ../../../Voltra/gpu.bend as V
import ./access.bend as Acc
import ../../../Auvia/model.bend as AM
import ../../../Auvia/kairo.bend as AK
import ../../../Auvia/field.bend as AF
import ../../../Auvia/service.bend as AS

# The integrated demo, GPU-presented: Ankra owns the window and its
# events, the text input and the clipboard, Kairo the interaction state
# and the editing, Tessra the layout, Runika, Syllo and Dithra the text,
# Ocula the PNG, Splina the SVG, Mokko the button and the text field,
# Chromi the frame as a draw list, and Voltra draws that list on the GPU.
# Auvia publishes it to assistive technologies (access.bend) and routes
# their requests through the same Kairo and field paths as the user's own
# input.
#
# The frame is redrawn only when something visible changed (hover, press,
# focus, a click, an edit, a new size, an expose); between changes the
# program waits for events without a deadline, on the window and on the
# accessibility bus at once (Ankra's `watch`). An edit redraws only the
# field and its note. The button and the field animate (Mokko's anim.bend:
# hover and press fades, focus rings, the caret blink): while one moves the
# loop draws on the monitor's refresh grid (Ankra's `animate`) and each
# frame redraws only that control; once all rest it waits again with no
# deadline. ECO_REDUCE_MOTION=1 makes every transition instant and the
# caret solid. Resize the window: the layout
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
  Demo{renderer: Gpu.Renderer, model: U.Model, shown: Fr.Frame, redraws: U32, started: Nat, clip: Clip.Clip,
    motion: U.Motion}

# The loop's state: the demo and its accessibility service, which owns a
# socket and so is not Data. `Alias` boxes the pair (nothing builds it), so
# the state crosses the loop as one pointer.
type Eco is Type:
  Eco{demo: Demo, a11y: AS.Service}
  Alias{eco: Eco}

def parts(e: Eco) -> Demo & AS.Service:
  match e:
    case Eco{d, s}:
      (d, s)
    case Alias{x}:
      parts(x)

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

# `motion`: the button stepped after each dispatch, at the batch's frame
# time, so a press and its release in one batch still show the press.
type Fold is Data:
  Fold{kairo: KT.State, activations: U32, dirty: Bool, edits: Edits, motion: U.Motion}

def changed(c: KT.Change) -> Bool:
  KT.Change{s, actions, dirty, layout} = c
  layout || Bool.not(U32.is_eq(U32.from_nat(List.length(&2, TG.Rect, dirty)), 0))

def activated(c: KT.Change) -> U32:
  KT.Change{s, actions, dirty, layout} = c
  K.activation_count(actions)

def actions_of(c: KT.Change) -> +List<KT.Action>:
  KT.Change{s, actions, dirty, layout} = c
  actions

def fold(xs: List<&2, KT.Input>, +font: F.Font, +at: TG.Rect, +now: U32, f: Fold) -> Fold:
  match xs:
    case Nil{}:
      f
    case Con{x, rest}:
      Fold{k, +a, +d, e, mo} = f
      +c = K.dispatch(k, x)
      +k1 = K.next(c)
      fold(rest, font, at, now, Fold{k1, (a + activated(c) : U32), d || changed(c),
        feed(actions_of(c), font, at, e), U.pressed(mo, k1, now)})

# Requests from assistive technologies join the batch after the window's
# input: a button or focus request goes through Kairo as a click or Tab
# would (Auvia's `route`), a text request through the field at its bounds
# as typing does (Auvia's `edit`), so the same refusals apply. Each verdict
# is kept for the service (`settle`).
type Verdict is Data:
  Verdict{request: AM.Request, ok: Bool}

type Heard is Data:
  Heard{fold: Fold, verdicts: List<&2, Verdict>}

def routed(got: AK.Routed, +font: F.Font, +at: TG.Rect, +a: U32, +d: Bool, e: Edits, mo: U.Motion) -> Fold & Bool:
  AK.Routed{+c, ok} = got
  (Fold{K.next(c), (a + activated(c) : U32), d || changed(c), feed(actions_of(c), font, at, e), mo}, ok)

def edited(got: AF.Edited, +k: KT.State, +a: U32, +d: Bool, +was: Bool, rs: List<&2, KE.Request>, mo: U.Motion) -> Fold & Bool:
  AF.Edited{FL.Fed{f, +dirty, r}, ok} = got
  (Fold{k, a, d, Edits{f, was || dirty, request.push(r, rs)}, mo}, ok)

def hear.of(r: AM.Request, +font: F.Font, +at: TG.Rect, +k: KT.State, +a: U32, +d: Bool, e: Edits, mo: U.Motion) -> Fold & Bool:
  match r:
    case AM.EditText{id, op, t}:
      Edits{field, +was, rs} = e
      edited(AF.edit(font, U.field_px(), at, k, U.field_id(), field, {AM.EditText{id, op, t} : AM.Request}), k, a, d, was, rs, mo)
    case AM.Activate{id, i}:
      routed(AK.route(k, {AM.Activate{id, i} : AM.Request}), font, at, a, d, e, mo)
    case AM.Focus{id}:
      routed(AK.route(k, {AM.Focus{id} : AM.Request}), font, at, a, d, e, mo)

def heard(+r: AM.Request, got: Fold & Bool, vs: List<&2, Verdict>) -> Heard:
  (f, ok) = got
  Heard{f, Con{Verdict{r, ok}, vs}}

def hear(rs: List<&2, AM.Request>, +font: F.Font, +at: TG.Rect, h: Heard) -> Heard:
  match rs:
    case Nil{}:
      h
    case Con{+r, rest}:
      Heard{Fold{+k, +a, +d, e, mo}, vs} = h
      hear(rest, font, at, heard(r, hear.of(r, font, at, k, a, d, e, mo), vs))

def heard_fold(h: Heard) -> Fold:
  Heard{f, vs} = h
  f

# Whether the batch changed what the controls show or say.
def fold_changed(f: Fold) -> Bool:
  Fold{k, +a, d, Edits{field, edited, rs}, mo} = f
  d || edited || U32.is_gt(a, 0)

def heard_verdicts(h: Heard) -> List<&2, Verdict>:
  Heard{f, vs} = h
  List.reverse(&2, Verdict, vs)

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

# Motion
# ------

# One frame in ms at the window's monitor refresh (mHz); 60 Hz unknown.
def frame_ms.of(unknown: Bool, +mhz: U32) -> U32:
  match unknown:
    case True{}:
      16
    case False{}:
      (1000000 / mhz : U32)

def frame_ms(+win: A.Win) -> U32:
  +mhz = A.refresh(win)
  frame_ms.of(U32.is_eq(mhz, 0), mhz)

# The time of the frame on screen when `update` runs: one frame before the
# frame time (while animating, update sees the next frame's grid time; at
# rest, the moment of the input, drawn at once). Motions retarget there, so
# the first frame drawn already moves: retargeted at the frame time itself,
# a motion is drawn first at its start value, and every animation began
# with a frame that changed no pixel.
def on_screen(+win: A.Win) -> U32:
  (A.frame_time(win) - frame_ms(win) : U32)

# A deadline `wait` ms away is due by the next frame (or already past).
def soon(+wait: U32, +fm: U32) -> Bool:
  U32.is_le(wait, fm) || U32.is_ge(wait, 2147483648)

def answer.at(+app: Demo, +redraw: Bool, due: Bool, +wait: U32) -> Loop.Step<Demo>:
  match due:
    case True{}:
      Loop.animate(Demo, app)
    case False{}:
      Bool.pick(Loop.Step<Demo>, redraw, Loop.Redraw{app}, Loop.Sleep{app, wait})

# The loop's answer from the motion's next deadline at `now`: animate while
# a control moves (a frame per refresh), a timer while the caret waits
# between fades (or a redraw, whose draw sets the timer again), and as
# before (Redraw or Keep: no deadline) once everything rests.
def answer(+app: Demo, +redraw: Bool, next: Maybe<&2, U32>, +now: U32, +fm: U32) -> Loop.Step<Demo>:
  match next:
    case None{}:
      decide(app, redraw)
    case Some{+t}:
      answer.at(app, redraw, soon((t - now : U32), fm), (t - now : U32))

def refielded(edited: Bool, +m: U.Model, +f: FL.Field) -> IO(U.Model):
  match edited:
    case False{}:
      IO.pure(U.Model, m)
    case True{}:
      relaid(U.refield(m, f))

# The controls' motion heads for the batch's outcome at the frame time.
def update.served(+win: A.Win, +es: List<&2, A.Input>, app: Demo, +a: U32, +d: Bool, +now: Nat, s: Served, mo: U.Motion) -> IO(Loop.Step<Demo>):
  Demo{+r, +m, shown, n, +t, old, was} = app
  Served{clip, +k, Edits{+field, +edited, rs}} = s
  +w = A.width(win)
  +h = A.height(win)
  +sized = other_size(m, w, h)
  +again = sized || U32.is_gt(a, 0)
  +ft = A.frame_time(win)
  +mo1 = U.stepped(mo, k, field, on_screen(win))
  do IO<Loop.Step<Demo>>:
    logged(es, Nat.sub(now, t), a, field_word(edited, field))
    +r1 : Gpu.Renderer <- resized(sized, r, w, h)
    +m1 : U.Model <- refielded(edited, U.with_kairo(m, k), field)
    +m2 : U.Model <- remodel(again, m1, w, h, (U.clicks(m) + a : U32))
    return answer(Demo{r1, m2, shown, n, t, clip, mo1}, d || edited || again || A.exposed(es) || Gpu.pending(r1),
      U.next_at(mo1, ft, frame_ms(win)), ft, frame_ms(win))

# Kairo's actions reach the field; the clipboard answers other clients
# (serve) and the field's requests (copy, paste).
# Small views of the app. The Demo is wide (the model is flattened into
# it), so no def holds the Demo and its model at once.
def model_of(a: Demo) -> U.Model:
  Demo{r, m, s, n, t, c, mo} = a
  m

def clip_of(a: Demo) -> Clip.Clip:
  Demo{r, m, s, n, t, c, mo} = a
  c

def font_of(a: Demo) -> F.Font:
  Demo{r, m, s, n, t, c, mo} = a
  U.font_of(m)

def field_at(a: Demo) -> TG.Rect:
  Demo{r, m, s, n, t, c, mo} = a
  U.field_at(m)

def started_fold(a: Demo) -> Fold:
  Demo{r, +m, s, n, t, c, mo} = a
  Fold{U.kairo(m), 0, False{}, Edits{U.field_of(m), False{}, Nil{}}, mo}

def update.folded(+win: A.Win, +es: List<&2, A.Input>, +app: Demo, +now: Nat, f: Fold) -> IO(Loop.Step<Demo>):
  Fold{k, +a, +d, Edits{field, edited, rs}, mo} = f
  do IO<Loop.Step<Demo>>:
    +c1 : Clip.Clip <- Clip.serve(win, clip_of(app), es)
    +s : Served <- requested(List.reverse(&2, KE.Request, rs), win, font_of(app), field_at(app),
      Served{c1, k, Edits{field, edited, Nil{}}})
    update.served(win, es, app, a, d, now, s, mo)

# Accessibility
# -------------

# The window's last reported position in a batch, for screen coordinates.
type Spot is Data:
  Spot{x: F32, y: F32}

def moved(es: List<&2, A.Input>, last: Maybe<&2, Spot>) -> Maybe<&2, Spot>:
  match es:
    case Nil{}:
      last
    case Con{A.Moved{x, y}, rest}:
      moved(rest, Some{Spot{x, y}})
    case Con{e, rest}:
      moved(rest, last)

def placed(m: Maybe<&2, Spot>, svc: AS.Service) -> AS.Service:
  match m:
    case None{}:
      svc
    case Some{Spot{x, y}}:
      AS.moved(svc, x, y)

def focus_changed(es: List<&2, A.Input>) -> Bool:
  match es:
    case Nil{}:
      False{}
    case Con{A.Focused{g}, rest}:
      True{}
    case Con{e, rest}:
      focus_changed(rest)

def settle_all(vs: List<&2, Verdict>, svc: AS.Service) -> AS.Service:
  match vs:
    case Nil{}:
      svc
    case Con{Verdict{r, ok}, rest}:
      settle_all(rest, AS.settle(svc, r, ok))

def op_word(op: AM.TextOp) -> String:
  match op:
    case AM.SetCaret{o}:
      "caret"
    case AM.Select{a, b}:
      "select"
    case AM.SetContents{t}:
      "set text"
    case AM.Insert{o, t}:
      "insert \"" ++ t ++ "\""
    case AM.Delete{a, b}:
      "delete " ++ U32.show(a) ++ "-" ++ U32.show(b)
    case AM.Copy{a, b}:
      "copy"
    case AM.Cut{a, b}:
      "cut"
    case AM.Paste{o}:
      "paste"

def request_word(r: AM.Request) -> String:
  match r:
    case AM.Activate{id, i}:
      "activate " ++ U32.show(id)
    case AM.Focus{id}:
      "focus " ++ U32.show(id)
    case AM.EditText{id, op, t}:
      "text " ++ U32.show(id) ++ " " ++ op_word(op)

def said(vs: List<&2, Verdict>) -> IO(Unit):
  match vs:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{Verdict{r, ok}, rest}:
      do IO<Unit>:
        IO.print("a11y: " ++ request_word(r) ++ Bool.pick(String, ok, " done", " refused"))
        said(rest)

# The tree goes out after anything that may have changed what it says: a
# redraw, a request, a change of window focus, a Kairo change or an edit
# (which may start an animation instead of a redraw). Animated frames alone
# do not publish. An unchanged tree sends nothing.
def told(publish: Bool, +win: A.Win, d: Demo, svc: AS.Service) -> IO(AS.Service):
  match publish:
    case False{}:
      IO.pure(AS.Service, svc)
    case True{}:
      AS.publish(svc, Acc.tree(model_of(d), title(), A.focused(win)))

def announced(+win: A.Win, step: Loop.Step<Demo>, svc: AS.Service, +asked: Bool) -> IO(Loop.Step<Eco>):
  match step:
    case Loop.Keep{+d}:
      do IO<Loop.Step<Eco>>:
        s : AS.Service <- told(asked, win, d, svc)
        return Loop.Keep{Eco{d, s}}
    case Loop.Redraw{+d}:
      do IO<Loop.Step<Eco>>:
        s : AS.Service <- told(True{}, win, d, svc)
        return Loop.Redraw{Eco{d, s}}
    case Loop.Sleep{+d, ms}:
      do IO<Loop.Step<Eco>>:
        s : AS.Service <- told(asked, win, d, svc)
        return Loop.Sleep{Eco{d, s}, ms}
    case Loop.Stop{+d}:
      do IO<Loop.Step<Eco>>:
        s : AS.Service <- told(asked, win, d, svc)
        return Loop.Stop{Eco{d, s}}

def attended(+win: A.Win, +es: List<&2, A.Input>, +app: Demo, +now: Nat, inputs: List<&2, KT.Input>,
  svc: AS.Service, +rs: List<&2, AM.Request>) -> IO(Loop.Step<Eco>):
  +h = hear(rs, font_of(app), field_at(app), Heard{fold(inputs, font_of(app), field_at(app), on_screen(win),
    started_fold(app)), Nil{}})
  do IO<Loop.Step<Eco>>:
    said(heard_verdicts(h))
    step : Loop.Step<Demo> <- update.folded(win, es, app, now, heard_fold(h))
    announced(win, step, settle_all(heard_verdicts(h), svc), Bool.not(List.is_empty(&2, AM.Request, rs)) ||
      focus_changed(es) || fold_changed(heard_fold(h)))

def pumped(+win: A.Win, +es: List<&2, A.Input>, +app: Demo, +now: Nat, inputs: List<&2, KT.Input>,
  got: AS.Service & List<&2, AM.Request>) -> IO(Loop.Step<Eco>):
  (svc, rs) = got
  attended(win, es, app, now, inputs, svc, rs)

# One turn: the window's events through Kairo and the field, then what
# assistive technologies asked (each request once, in arrival order); a
# new size or a click redoes the layout, an edit the field's text and
# note. The bus is read every turn; it ends the wait itself when a call
# arrives.
def update.eco(win: A.Win, batch: List<&2, A.Input>, p: Demo & AS.Service) -> IO(Loop.Step<Eco>):
  (app, svc) = p
  +es = batch
  do IO<Loop.Step<Eco>>:
    +now : Nat <- IO.now()
    +inputs : List<&2, KT.Input> <- need(List<&2, KT.Input>, AA.normalize(es, 1.0))
    got : AS.Service & List<&2, AM.Request> <- AS.pump(placed(moved(es, None{}), svc))
    pumped(win, es, app, now, inputs, got)

def update(win: A.Win, batch: List<&2, A.Input>, state: Eco) -> IO(Loop.Step<Eco>):
  update.eco(win, batch, parts(state))

# Drawing
# -------

def report(+n: U32, +ms: Nat, +r: Gpu.Renderer, +m: U.Model, +since: Nat, +damage: U32, +shown: Bool) -> IO(Unit):
  IO.print("redraw " ++ U32.show(n) ++ " at " ++ Nat.show(since) ++ " ms: scene + GPU " ++ Nat.show(ms) ++
    " ms, " ++ Bool.pick(String, Gpu.last_partial(r), "damage only (" ++ U32.show(damage) ++ " px), ", "whole, ") ++
    Bool.pick(String, shown, "", "not presented, ") ++
    U32.show(Gpu.last_quads(r)) ++ " quads, " ++ U32.show(U.glyphs(m)) ++ " glyphs cached, atlas " ++
    U32.show(Gpu.entries(r)) ++ " entries, " ++ U32.show(Gpu.uploaded(r)) ++ " texels uploaded")

def drawn(+win: A.Win, got: Gpu.Renderer & Fr.Frame, +m: U.Model, +n: U32, +t: Nat, +t0: Nat, +damage: U32, clip: Clip.Clip,
  +mo: U.Motion, +now: U32, +presents: U32) -> IO(Loop.Step<Demo>):
  (+r1, shown) = got
  do IO<Loop.Step<Demo>>:
    +t1 : Nat <- IO.now()
    report((n + 1 : U32), Nat.sub(t1, t0), r1, m, Nat.sub(t1, t), damage, U32.is_ne(V.drawn(Gpu.gpu(r1)), presents))
    return answer(Demo{r1, m, shown, (n + 1 : U32), t, clip, mo}, Gpu.pending(r1), U.next_at(mo, now, frame_ms(win)), now,
      frame_ms(win))

# The frame is retained (Chromi's frame.bend): only what changed since the
# last one is planned and redrawn. The report gives the damaged area in
# pixels (the regions a partial frame redraws); a frame with no damage is
# neither painted nor presented (Gpu.render), while the animation goes on.
# The controls are drawn at the frame's time (Ankra's frame_time: the
# refresh grid while animating).
def draw.demo(+win: A.Win, app: Demo) -> IO(Loop.Step<Demo>):
  Demo{+r, +m, last, +n, +t, clip, +mo} = app
  +now = A.frame_time(win)
  do IO<Loop.Step<Demo>>:
    +t0 : Nat <- IO.now()
    +f : Fr.Frame <- IO.pure(Fr.Frame, U.framed(m, last, mo, now))
    got : Gpu.Renderer & Fr.Frame <- Gpu.render(r, f)
    drawn(win, got, m, n, t, t0, Fr.area(Fr.regions(f), 0), clip, mo, now, V.drawn(Gpu.gpu(r)))

def rewrap(step: Loop.Step<Demo>, svc: AS.Service) -> Loop.Step<Eco>:
  match step:
    case Loop.Keep{d}:
      Loop.Keep{Eco{d, svc}}
    case Loop.Redraw{d}:
      Loop.Redraw{Eco{d, svc}}
    case Loop.Sleep{d, ms}:
      Loop.Sleep{Eco{d, svc}, ms}
    case Loop.Stop{d}:
      Loop.Stop{Eco{d, svc}}

def draw.eco(win: A.Win, p: Demo & AS.Service) -> IO(Loop.Step<Eco>):
  (app, svc) = p
  do IO<Loop.Step<Eco>>:
    step : Loop.Step<Demo> <- draw.demo(win, app)
    return rewrap(step, svc)

def draw(win: A.Win, state: Eco) -> IO(Loop.Step<Eco>):
  draw.eco(win, parts(state))

# Startup and teardown
# --------------------

def finish.demo(win: A.Win, app: Demo) -> IO(Unit):
  Demo{+r, +m, s, +n, t, c, mo} = app
  do IO<Unit>:
    IO.print("frames presented: " ++ U32.show(V.drawn(Gpu.gpu(r))) ++ ", redraws: " ++ U32.show(n) ++
      ", clicks: " ++ U32.show(U.clicks(m)))
    +report : V.Report <- Gpu.close(r)
    IO.print(V.report.show(report))
    +left : U32 <- A.close(win)
    IO.print("window objects left: " ++ U32.show(left))

# The accessibility connection is closed first, then the GPU and the window.
def finish.eco(win: A.Win, p: Demo & AS.Service) -> IO(Unit):
  (app, svc) = p
  do IO<Unit>:
    AS.stop(svc)
    IO.print("accessibility connection closed")
    finish.demo(win, app)

def finish(end: A.Win & Eco) -> IO(Unit):
  (win, state) = end
  finish.eco(win, parts(state))

# An environment variable set to "1".
def logging(r: Result<&1, &1, U32 & String, String>) -> Bool:
  match r:
    case Fail{e}:
      False{}
    case Done{v}:
      String.eq(v, "1")

def reported(got: AS.Service & String) -> IO(AS.Service):
  (svc, text) = got
  do IO<AS.Service>:
    IO.print("accessibility " ++ text)
    return svc

# The loop also wakes when the accessibility bus has something to read.
def watching.if(none: Bool, +win: A.Win, fd: U32) -> IO(A.Win):
  match none:
    case True{}:
      IO.pure(A.Win, win)
    case False{}:
      A.watch(win, fd)

def watching(+win: A.Win, +fd: U32) -> IO(A.Win):
  watching.if(U32.is_eq(fd, A.unwatched()), win, fd)

def run(+win: A.Win, demo: Demo, got: AS.Service & U32) -> IO(Unit):
  (a11y, fd) = got
  do IO<Unit>:
    +w : A.Win <- watching(win, fd)
    end : A.Win & Eco <- Loop.run(~Eco, ~update, ~draw, w, Eco{demo, a11y})
    finish(end)

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
    log : Result<&1, &1, U32 & String, String> <- IO.get_env("AUVIA_LOG")
    a11y : AS.Service <- AS.start(Acc.tree(model, title(), A.focused(win)), logging(log))
    a11y : AS.Service <- reported(AS.status(a11y))
    got : AS.Service & U32 <- AS.descriptor(a11y)
    reduce : Result<&1, &1, U32 & String, String> <- IO.get_env("ECO_REDUCE_MOTION")
    +reduced : Bool <- IO.pure(Bool, logging(reduce))
    IO.print("motion: " ++ Bool.pick(String, reduced, "reduced (ECO_REDUCE_MOTION=1)", "on"))
    run(win, Demo{r, model, Fr.none(), 0, t0, Clip.none(), U.motion(MA.Prefs{reduced, True{}})}, got)
