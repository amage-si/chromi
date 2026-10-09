import Base
import ../../scene.bend as S
import ../../geometry.bend as G
import ../../frame.bend as Fr
import ./text.bend as T
import ./media.bend as Media
import ../../../Runika/font.bend as F
import ../../../Tessra/main.bend as L
import ../../../Tessra/geometry.bend as TG
import ../../../Kairo/types.bend as KT
import ../../../Kairo/main.bend as K
import ../../../Mokko/main.bend as M
import ../../../Mokko/field.bend as FL
import ../../../Kairo/edit.bend as KE

# The integrated demo's model, layout and frame, independent of how the
# frame reaches the screen (GPU: eco/main.bend; CPU: eco/cpu.bend).
#
# Tessra places a text column (title, subtitle, wrapped body, Mokko
# button, status, Mokko text field and its note) beside a media column
# (the PNG and the SVG with their captions) when the panel is wide, and
# stacks them when it is narrow. Any size change redoes the layout and
# moves Kairo's button and field; a click redoes the status text; an edit
# redoes the field's text run and its note. Glyphs reach the cache once
# per size.

def background() -> U32:
  219422463

def panel_color() -> U32:
  354033919

def line_color() -> U32:
  825901311

def accent() -> U32:
  1089715967

def heart_color() -> U32:
  4082194431

def ink() -> U32:
  4008835583

def muted() -> U32:
  2965424895

def button_id() -> U32:
  4

def field_id() -> U32:
  12

def note_id() -> U32:
  13

# The field's font size, and the widest the field gets.
def field_px() -> F32:
  18.0

def field_width() -> F32:
  360.0

def error_color() -> U32:
  4031927039

# Strings
# -------

def title() -> String:
  "AMAGE Eco"

def subtitle() -> String:
  "Uma janela, uma GPU, várias bibliotecas."

def body() -> String:
  "Texto real em Bend: ação, coração, café. A Ankra cuida da janela e dos eventos, a Voltra da GPU e o Chromi da lista de desenho."

def label() -> String:
  "Ativar"

def status(+n: U32) -> String:
  Bool.pick(String, U32.is_eq(n, 0), "Clique no botão ou use Tab e Espaço.",
    "Ativado " ++ U32.show(n) ++ Bool.pick(String, U32.is_eq(n, 1), " vez.", " vezes."))

def field_name() -> String:
  "Texto livre"

def placeholder() -> String:
  "Escreva aqui"

def hint() -> String:
  "Tab foca o campo; Ctrl+C copia, Ctrl+V cola."

def png_caption() -> String:
  "PNG decodificado pela Ocula"

def svg_caption() -> String:
  "SVG interpretado pela Splina"

# Model
# -----

type Assets is Data:
  Assets{font: F.Font, picture: Media.Picture, heart: List<&2, Media.Shape>}

type Texts is Data:
  Texts{title: T.Run, subtitle: T.Run, body: T.Run, button: T.Run, status: T.Run,
    png: T.Run, svg: T.Run}

type Places is Data:
  Places{panel: TG.Rect, title: TG.Rect, subtitle: TG.Rect, body: TG.Rect, button: TG.Rect,
    status: TG.Rect, png: TG.Rect, png_caption: TG.Rect, svg: TG.Rect, svg_caption: TG.Rect}

# The text field (Mokko's field.bend), the runs of its text (or
# placeholder) and of its note, and where both sit. `Alias` makes the type
# recursive, so the compiler passes it as one pointer and the Model stays
# narrow; nothing builds an Alias, and the accessors answer for the one it
# wraps.
type Typing is Data:
  Typing{field: FL.Field, run: T.Run, note: T.Run, at: TG.Rect, note_at: TG.Rect}
  Alias{typing: Typing}

type Model is Data:
  Model{assets: Assets, cache: T.Cache, texts: Texts, places: Places,
    kairo: KT.State, clicks: U32, width: U32, height: U32, typing: Typing}

def f32(+n: U32) -> F32:
  U32.to_f32(n)

# Text
# ----

type Grown is Data:
  Grown{texts: Texts, cache: T.Cache}

def grow(p: T.Prepared) -> T.Run & T.Cache:
  T.Prepared{r, c} = p
  (r, c)

def run_of(p: T.Prepared) -> T.Run:
  T.Prepared{r, c} = p
  r

def cache_of(p: T.Prepared) -> T.Cache:
  T.Prepared{r, c} = p
  c

def texts(+font: F.Font, +column: F32, +clicks: U32, +cache: T.Cache) ->
  Result<&2, &2, String, Grown>:
  do Result<&2, &2, String, Grown>:
    +a : T.Prepared <- T.prepare(font, title(), 34.0, column, cache)
    +b : T.Prepared <- T.prepare(font, subtitle(), 19.0, column, cache_of(a))
    +c : T.Prepared <- T.prepare(font, body(), 16.0, column, cache_of(b))
    +d : T.Prepared <- T.prepare(font, label(), 18.0, 1000000.0, cache_of(c))
    +e : T.Prepared <- T.prepare(font, status(clicks), 16.0, column, cache_of(d))
    +f : T.Prepared <- T.prepare(font, png_caption(), 13.0, 1000000.0, cache_of(e))
    +g : T.Prepared <- T.prepare(font, svg_caption(), 13.0, 1000000.0, cache_of(f))
    return Grown{Texts{run_of(a), run_of(b), run_of(c), run_of(d), run_of(e), run_of(f), run_of(g)},
      cache_of(g)}

def metrics(+r: T.Run) -> M.Metrics:
  M.Metrics{T.width(r), T.height(r), T.ascent(r)}

def grown_texts(g: Grown) -> Texts:
  Grown{t, c} = g
  t

def grown_cache(g: Grown) -> T.Cache:
  Grown{t, c} = g
  c

# The field's run shows its text, or the placeholder while it is empty;
# the note shows the field's refusal message, or a hint.
def field_label(f: FL.Field) -> String:
  FL.Field{KE.Edit{text, +count, c, a}, stops, line, scroll, r} = f
  Bool.pick(String, U32.is_eq(count, 0), placeholder(), text)

def note_text(m: Maybe<&2, String>) -> String:
  match m:
    case Some{message}:
      message
    case None{}:
      hint()

def note_color(m: Maybe<&2, String>) -> U32:
  match m:
    case Some{message}:
      error_color()
    case None{}:
      muted()

type Typed is Data:
  Typed{run: T.Run, note: T.Run, cache: T.Cache}

def typed(+font: F.Font, +f: FL.Field, +column: F32, +cache: T.Cache) -> Result<&2, &2, String, Typed>:
  do Result<&2, &2, String, Typed>:
    +a : T.Prepared <- T.prepare(font, field_label(f), field_px(), 1000000.0, cache)
    +b : T.Prepared <- T.prepare(font, note_text(FL.message(f)), 14.0, column, cache_of(a))
    return Typed{run_of(a), run_of(b), cache_of(b)}

def typed_note(y: Typed) -> T.Run:
  Typed{r, n, c} = y
  n

# Layout
# ------

def panel(+w: U32, +h: U32) -> TG.Rect:
  TG.Rect{24.0, 24.0, F32.max(0.0, (f32(w) - 48.0 : F32)), F32.max(0.0, (f32(h) - 48.0 : F32))}

def content(+w: U32, +h: U32) -> TG.Rect:
  TG.inset(panel(w, h), TG.Insets{32.0, 32.0, 32.0, 32.0})

def media_width() -> F32:
  256.0

def wide(+w: U32) -> Bool:
  (f32(w) >= 760.0 : F32)

# The text column's width: beside the media when wide, the whole content
# width when narrow.
def column(+w: U32) -> F32:
  +cw = F32.max(1.0, (f32(w) - 112.0 : F32))
  Bool.pick(F32, wide(w), F32.max(120.0, (cw - media_width() - 40.0 : F32)), cw)

def child(+id: U32, s: TG.Size) -> L.Child:
  L.Child{id, s, L.unconstrained()}

def text_child(+id: U32, r: T.Run) -> L.Child:
  child(id, M.text_size(metrics(r)))

def left_children(t: Texts, +field: TG.Size, note: T.Run) -> +List<L.Child>:
  Texts{a, b, c, +d, e, f, g} = t
  [text_child(1, a), text_child(2, b), text_child(3, c), child(4, M.button_size(metrics(d))),
    text_child(5, e), child(field_id(), field), text_child(note_id(), note)]

# The field is as tall as Mokko asks for a line of the button's size and
# as wide as the column allows, up to field_width().
def field_box(t: Texts, +w: U32) -> TG.Size:
  Texts{a, b, c, +d, e, f, g} = t
  FL.field_size(T.height(d), F32.min(column(w), field_width()))

def right_children(t: Texts) -> +List<L.Child>:
  Texts{a, b, c, d, e, f, g} = t
  [child(6, TG.Size{media_width(), 256.0}), text_child(7, f), child(8, TG.Size{96.0, 96.0}),
    text_child(9, g)]

def config(axis: L.Axis, align: L.Align) -> L.Config:
  L.Config{axis, TG.Insets{0.0, 0.0, 0.0, 0.0}, 14.0, L.Leading{}, align}

def solved(r: Result<&2, &2, L.Error, L.Layout>) -> Result<&2, &2, String, +List<L.Placement>>:
  match r:
    case Fail{e}:
      Fail{"demo: Tessra rejected the layout"}
    case Done{L.Layout{c, ps, overflow}}:
      Done{ps}

def place(ps: +List<L.Placement>, +id: U32) -> TG.Rect:
  Maybe.default(&2, TG.Rect, L.find(ps, id), TG.Rect{0.0, 0.0, 0.0, 0.0})

def places.of(+w: U32, +h: U32, +left: +List<L.Placement>, +right: +List<L.Placement>) -> Places:
  Places{panel(w, h), place(left, 1), place(left, 2), place(left, 3), place(left, 4), place(left, 5),
    place(right, 6), place(right, 7), place(right, 8), place(right, 9)}

# The media column right of the text when wide; below it, centered, when narrow.
def media_box.of(+broad: Bool, r: TG.Rect) -> TG.Rect:
  TG.Rect{+cx, +cy, +cw, +ch} = r
  Bool.pick(TG.Rect, broad, TG.Rect{(cx + cw - media_width() : F32), cy, media_width(), ch},
    TG.Rect{cx, (cy + F32.max(0.0, (ch - 420.0 : F32)) : F32), cw, F32.min(ch, 420.0)})

def media_box(+w: U32, +h: U32) -> TG.Rect:
  media_box.of(wide(w), content(w, h))

def text_box.of(+broad: Bool, +column: F32, r: TG.Rect) -> TG.Rect:
  TG.Rect{+cx, +cy, +cw, +ch} = r
  Bool.pick(TG.Rect, broad, TG.Rect{cx, cy, column, ch},
    TG.Rect{cx, cy, cw, F32.max(0.0, (ch - 420.0 : F32))})

def text_box(+w: U32, +h: U32) -> TG.Rect:
  text_box.of(wide(w), column(w), content(w, h))

# The places of the content, and of the field and its note.
type Arranged is Data:
  Arranged{places: Places, field: TG.Rect, note: TG.Rect}

def arranged.of(+w: U32, +h: U32, +left: +List<L.Placement>, +right: +List<L.Placement>) -> Arranged:
  Arranged{places.of(w, h, left, right), place(left, field_id()), place(left, note_id())}

def arrange(+t: Texts, +note: T.Run, +w: U32, +h: U32) -> Result<&2, &2, String, Arranged>:
  do Result<&2, &2, String, Arranged>:
    +left : +List<L.Placement> <- solved(L.layout(text_box(w, h), config(L.Column{}, L.Start{}),
      left_children(t, field_box(t, w), note)))
    +right : +List<L.Placement> <- solved(L.layout(media_box(w, h),
      config(L.Column{}, L.Center{}), right_children(t)))
    return arranged.of(w, h, left, right)

def button_node(+r: TG.Rect) -> KT.Node:
  KT.Node{button_id(), r, label(), KT.ButtonRole{}, True{}, True{}}

def places_button(p: Places) -> TG.Rect:
  Places{pa, a, b, c, button, e, f, g, h, i} = p
  button

def field_node(+r: TG.Rect) -> KT.Node:
  FL.field_node(field_id(), r, field_name())

def arranged_button(a: Arranged) -> TG.Rect:
  Arranged{p, f, n} = a
  places_button(p)

def arranged_field(a: Arranged) -> TG.Rect:
  Arranged{p, f, n} = a
  f

# Building and rebuilding
# -----------------------

def started(r: Result<&2, &2, KT.Error, KT.State>) -> Result<&2, &2, String, KT.State>:
  match r:
    case Fail{e}:
      Fail{"demo: Kairo rejected the button"}
    case Done{s}:
      Done{s}

def assembled(a: Assets, t: Texts, y: Typed, r: Arranged, +k: KT.State, f: FL.Field, +clicks: U32, +w: U32, +h: U32) -> Model:
  Typed{run, note, c} = y
  Arranged{p, fa, na} = r
  Model{a, c, t, p, k, clicks, w, h, Typing{f, run, note, fa, na}}

# The model at a w x h window, from scratch, with an empty field.
def build(+a: Assets, +w: U32, +h: U32) -> Result<&2, &2, String, Model>:
  Assets{+font, pic, heart} = a
  do Result<&2, &2, String, Model>:
    +g : Grown <- texts(font, column(w), 0, T.cache())
    +f : FL.Field <- FL.field(font, field_px(), "")
    +y : Typed <- typed(font, f, column(w), grown_cache(g))
    +p : Arranged <- arrange(grown_texts(g), typed_note(y), w, h)
    +k : KT.State <- started(K.init([button_node(arranged_button(p)), field_node(arranged_field(p))], f32(w), f32(h)))
    return assembled(a, grown_texts(g), y, p, k, f, 0, w, h)

def moved(r: Result<&2, &2, KT.Error, KT.Change>, +old: KT.State) -> KT.State:
  match r:
    case Fail{e}:
      old
    case Done{c}:
      K.next(c)

# Kairo's button and field moved to their new places.
def relocated(+k: KT.State, +p: Arranged) -> KT.State:
  +k1 = moved(K.set_bounds(k, button_id(), arranged_button(p)), k)
  moved(K.set_bounds(k1, field_id(), arranged_field(p)), k1)

# The texts after a new click count at the same column width: only the
# status line is laid out again; the other runs are kept as they were.
def restatus(+font: F.Font, +column: F32, +clicks: U32, +cache: T.Cache, t: Texts) ->
  Result<&2, &2, String, Grown>:
  Texts{a, b, c, d, old, f, g} = t
  do Result<&2, &2, String, Grown>:
    +e : T.Prepared <- T.prepare(font, status(clicks), 16.0, column, cache)
    return Grown{Texts{a, b, c, d, run_of(e), f, g}, cache_of(e)}

def retext(same: Bool, +font: F.Font, +column: F32, +clicks: U32, +cache: T.Cache,
  t: Texts) -> Result<&2, &2, String, Grown>:
  match same:
    case True{}:
      restatus(font, column, clicks, cache, t)
    case False{}:
      texts(font, column, clicks, cache)

def typing_field(y: Typing) -> FL.Field:
  match y:
    case Typing{f, r, n, fa, na}:
      f
    case Alias{x}:
      typing_field(x)

def typing_at(y: Typing) -> TG.Rect:
  match y:
    case Typing{f, r, n, fa, na}:
      fa
    case Alias{x}:
      typing_at(x)

# Redoes the layout for a new size or a new click count (the text too for
# a new column width, else only the status line), and moves Kairo's button
# and field to their new places.
def rebuild(+m: Model, +w: U32, +h: U32, +clicks: U32) -> Result<&2, &2, String, Model>:
  Model{+a, +cache, t, p, +k, n, +ow, oh, y} = m
  Assets{+font, pic, heart} = a
  +f = typing_field(y)
  do Result<&2, &2, String, Model>:
    +g : Grown <- retext(F32.is_eq(column(ow), column(w)), font, column(w), clicks, cache, t)
    +ty : Typed <- typed(font, f, column(w), grown_cache(g))
    +places : Arranged <- arrange(grown_texts(g), typed_note(ty), w, h)
    return assembled(a, grown_texts(g), ty, places, relocated(k, places), f, clicks, w, h)

# The model with an edited field: its text run and note are prepared
# again (from the cache when seen before) and the column laid out again
# (the note may change size; it is the column's last child).
def refield(+m: Model, +f: FL.Field) -> Result<&2, &2, String, Model>:
  Model{+a, +cache, +t, p, +k, n, +w, +h, y} = m
  Assets{+font, pic, heart} = a
  do Result<&2, &2, String, Model>:
    +ty : Typed <- typed(font, f, column(w), cache)
    +places : Arranged <- arrange(t, typed_note(ty), w, h)
    return assembled(a, t, ty, places, relocated(k, places), f, n, w, h)

# Accessors
# ---------

def size_of(m: Model) -> U32 & U32:
  Model{a, c, t, p, k, n, w, h, y} = m
  (w, h)

def kairo(m: Model) -> KT.State:
  Model{a, c, t, p, k, n, w, h, y} = m
  k

def clicks(m: Model) -> U32:
  Model{a, c, t, p, k, n, w, h, y} = m
  n

def with_kairo(m: Model, +k: KT.State) -> Model:
  Model{a, c, t, p, old, n, w, h, y} = m
  Model{a, c, t, p, k, n, w, h, y}

def glyphs(m: Model) -> U32:
  Model{a, c, t, p, k, n, w, h, y} = m
  T.glyph_count(c)

def font_of(m: Model) -> F.Font:
  Model{Assets{f, pic, heart}, c, t, p, k, n, w, h, y} = m
  f

# The text field and the bounds it is fed and drawn with.
def field_of(m: Model) -> FL.Field:
  Model{a, c, t, p, k, n, w, h, y} = m
  typing_field(y)

def field_at(m: Model) -> TG.Rect:
  Model{a, c, t, p, k, n, w, h, y} = m
  typing_at(y)

# The frame
# ---------

def crect(r: TG.Rect) -> G.Rect:
  TG.Rect{x, y, w, h} = r
  G.Rect{x, y, w, h}

def at(s: S.Scene, run: T.Run, r: TG.Rect, +color: U32) -> S.Scene:
  TG.Rect{x, y, w, h} = r
  T.paint(s, run, x, y, color)

# Mokko's button primitives, drawn with rounded corners.
def primitives(ps: +List<M.Primitive>, s: S.Scene, +run: T.Run) -> S.Scene:
  match ps:
    case Nil{}:
      s
    case Con{M.Fill{r, color}, rest}:
      primitives(rest, S.round_rect(s, crect(r), 10.0, color), run)
    case Con{M.Stroke{r, width, color}, rest}:
      primitives(rest, S.border(s, crect(r), 9.0, width, color), run)
    case Con{M.TextRun{x, top, baseline, l, size, clip, color}, rest}:
      c = S.clip_rect(s, crect(clip))
      c = T.paint(c, run, x, top, color)
      primitives(rest, S.reset_clip(c), run)

def button(v: Result<&2, &2, String, M.View>, s: S.Scene, +run: T.Run) -> S.Scene:
  match v:
    case Fail{message}:
      S.reject(s, message)
    case Done{M.View{ps, semantic}}:
      primitives(ps, s, run)

# Mokko's field primitives, drawn square: the box, the border, the
# selection band and the caret are plain rectangles; the text run (`run`,
# prepared for the primitive's label) is clipped to the text area.
def field_primitives(ps: +List<M.Primitive>, s: S.Scene, +run: T.Run) -> S.Scene:
  match ps:
    case Nil{}:
      s
    case Con{M.Fill{r, color}, rest}:
      field_primitives(rest, S.fill_rect(s, crect(r), color), run)
    case Con{M.Stroke{r, width, color}, rest}:
      field_primitives(rest, S.stroke_rect(s, crect(r), width, color), run)
    case Con{M.TextRun{x, top, baseline, l, size, clip, color}, rest}:
      c = S.clip_rect(s, crect(clip))
      c = T.paint(c, run, x, top, color)
      field_primitives(rest, S.reset_clip(c), run)

def field_paint(v: Result<&2, &2, String, FL.FieldView>, s: S.Scene, +run: T.Run) -> S.Scene:
  match v:
    case Fail{message}:
      S.reject(s, message)
    case Done{FL.FieldView{M.View{ps, semantic}, edit}}:
      field_primitives(ps, s, run)

def field_drawn(y: Typing, k: KT.State, s: S.Scene) -> S.Scene:
  match y:
    case Typing{f, run, note, +fa, na}:
      field_paint(FL.view(field_node(fa), k, f, field_px(), FL.field_theme(), placeholder()), s, run)
    case Alias{x}:
      field_drawn(x, k, s)

def note_drawn(y: Typing, s: S.Scene) -> S.Scene:
  match y:
    case Typing{f, run, note, fa, na}:
      at(s, note, na, note_color(FL.message(f)))
    case Alias{x}:
      note_drawn(x, s)

def rx(r: TG.Rect) -> F32:
  TG.Rect{x, y, w, h} = r
  x

def ry(r: TG.Rect) -> F32:
  TG.Rect{x, y, w, h} = r
  y

def frame(m: Model) -> S.Scene:
  Model{Assets{f, pic, heart}, cache, Texts{a, b, c, +d, e, pg, sv},
    Places{+panel, +ta, tb, tc, +bt, te, +pic_at, pic_cap, +svg_at, svg_cap}, +k, n, +w, +h, +y} = m
  s = S.new(w, h, 1.0, background())
  s = S.round_rect(s, crect(panel), 18.0, panel_color())
  s = S.border(s, crect(panel), 18.0, 1.0, line_color())
  s = S.fill_rect(s, G.Rect{rx(ta), (ry(ta) - 14.0 : F32), 64.0, 4.0}, accent())
  s = at(s, a, ta, ink())
  s = at(s, b, tb, muted())
  s = at(s, c, tc, ink())
  s = button(M.button(button_node(bt), k, metrics(d), 18.0, M.theme()), s, d)
  s = at(s, e, te, muted())
  s = field_drawn(y, k, s)
  s = note_drawn(y, s)
  s = Media.paint_picture(s, pic, rx(pic_at), ry(pic_at))
  s = at(s, pg, pic_cap, muted())
  s = Media.paint_svg(s, heart, rx(svg_at), ry(svg_at))
  at(s, sv, svg_cap, muted())

# The same drawing as retained parts (Chromi's frame.bend), keyed by the
# layout's child ids (the button and the field by their Kairo ids) and two
# of their own for the panel and the accent bar. Each part is recorded and compared every
# frame; only parts that changed are planned and redrawn.
def framed(m: Model, last: Fr.Frame) -> Fr.Frame:
  Model{Assets{f, pic, heart}, cache, Texts{a, b, c, +d, e, pg, sv},
    Places{+panel, +ta, tb, tc, +bt, te, +pic_at, pic_cap, +svg_at, svg_cap}, +k, n, +w, +h, +y} = m
  p = Fr.begin(last, w, h, 1.0, background())
  p = Fr.part(p, 10, s => S.border(S.round_rect(s, crect(panel), 18.0, panel_color()), crect(panel), 18.0,
    1.0, line_color()))
  p = Fr.part(p, 11, s => S.fill_rect(s, G.Rect{rx(ta), (ry(ta) - 14.0 : F32), 64.0, 4.0}, accent()))
  p = Fr.part(p, 1, s => at(s, a, ta, ink()))
  p = Fr.part(p, 2, s => at(s, b, tb, muted()))
  p = Fr.part(p, 3, s => at(s, c, tc, ink()))
  p = Fr.part(p, button_id(), s => button(M.button(button_node(bt), k, metrics(d), 18.0, M.theme()), s, d))
  p = Fr.part(p, 5, s => at(s, e, te, muted()))
  p = Fr.part(p, field_id(), s => field_drawn(y, k, s))
  p = Fr.part(p, note_id(), s => note_drawn(y, s))
  p = Fr.part(p, 6, s => Media.paint_picture(s, pic, rx(pic_at), ry(pic_at)))
  p = Fr.part(p, 7, s => at(s, pg, pic_cap, muted()))
  p = Fr.part(p, 8, s => Media.paint_svg(s, heart, rx(svg_at), ry(svg_at)))
  Fr.end(Fr.part(p, 9, s => at(s, sv, svg_cap, muted())))
