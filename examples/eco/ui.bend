import Base
import ../../scene.bend as S
import ../../geometry.bend as G
import ./text.bend as T
import ./media.bend as Media
import ../../../Runika/font.bend as F
import ../../../Tessra/main.bend as L
import ../../../Tessra/geometry.bend as TG
import ../../../Kairo/types.bend as KT
import ../../../Kairo/main.bend as K
import ../../../Mokko/main.bend as M

# The integrated demo's model, layout and frame, independent of how the
# frame reaches the screen (GPU: eco/main.bend; CPU: eco/cpu.bend).
#
# Tessra places a text column (title, subtitle, wrapped body, Mokko
# button, status) beside a media column (the PNG and the SVG with their
# captions) when the panel is wide, and stacks them when it is narrow. Any
# size change redoes the layout and moves Kairo's button; a click redoes
# the status text. Glyphs reach the cache once per size.

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

type Model is Data:
  Model{assets: Assets, cache: List<&2, T.Glyph>, texts: Texts, places: Places,
    kairo: KT.State, clicks: U32, width: U32, height: U32}

def f32(+n: U32) -> F32:
  U32.to_f32(n)

# Text
# ----

type Grown is Data:
  Grown{texts: Texts, cache: List<&2, T.Glyph>}

def grow(p: T.Prepared) -> T.Run & List<&2, T.Glyph>:
  T.Prepared{r, c} = p
  (r, c)

def run_of(p: T.Prepared) -> T.Run:
  T.Prepared{r, c} = p
  r

def cache_of(p: T.Prepared) -> List<&2, T.Glyph>:
  T.Prepared{r, c} = p
  c

def texts(+font: F.Font, +column: F32, +clicks: U32, +cache: List<&2, T.Glyph>) ->
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

def left_children(t: Texts) -> +List<L.Child>:
  Texts{a, b, c, +d, e, f, g} = t
  [text_child(1, a), text_child(2, b), text_child(3, c), child(4, M.button_size(metrics(d))),
    text_child(5, e)]

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

def arrange(+t: Texts, +w: U32, +h: U32) -> Result<&2, &2, String, Places>:
  do Result<&2, &2, String, Places>:
    +left : +List<L.Placement> <- solved(L.layout(text_box(w, h), config(L.Column{}, L.Start{}), left_children(t)))
    +right : +List<L.Placement> <- solved(L.layout(media_box(w, h),
      config(L.Column{}, L.Center{}), right_children(t)))
    return places.of(w, h, left, right)

def button_node(+r: TG.Rect) -> KT.Node:
  KT.Node{button_id(), r, label(), KT.ButtonRole{}, True{}, True{}}

def places_button(p: Places) -> TG.Rect:
  Places{pa, a, b, c, button, e, f, g, h, i} = p
  button

# Building and rebuilding
# -----------------------

def started(r: Result<&2, &2, KT.Error, KT.State>) -> Result<&2, &2, String, KT.State>:
  match r:
    case Fail{e}:
      Fail{"demo: Kairo rejected the button"}
    case Done{s}:
      Done{s}

def built(a: Assets, g: Grown, +p: Places, +k: KT.State, +clicks: U32, +w: U32, +h: U32) -> Model:
  Grown{t, c} = g
  Model{a, c, t, p, k, clicks, w, h}

def grown_texts(g: Grown) -> Texts:
  Grown{t, c} = g
  t

# The model at a w x h window, from scratch.
def build(+a: Assets, +w: U32, +h: U32) -> Result<&2, &2, String, Model>:
  Assets{+font, pic, heart} = a
  do Result<&2, &2, String, Model>:
    +g : Grown <- texts(font, column(w), 0, Nil{})
    +p : Places <- arrange(grown_texts(g), w, h)
    +k : KT.State <- started(K.init([button_node(places_button(p))], f32(w), f32(h)))
    return built(a, g, p, k, 0, w, h)

def moved(r: Result<&2, &2, KT.Error, KT.Change>, +old: KT.State) -> KT.State:
  match r:
    case Fail{e}:
      old
    case Done{c}:
      K.next(c)

# Redoes the text and the layout for a new size or a new click count, and
# moves Kairo's button to its new place.
def rebuild(+m: Model, +w: U32, +h: U32, +clicks: U32) -> Result<&2, &2, String, Model>:
  Model{+a, +cache, t, p, +k, n, ow, oh} = m
  Assets{+font, pic, heart} = a
  do Result<&2, &2, String, Model>:
    +g : Grown <- texts(font, column(w), clicks, cache)
    +places : Places <- arrange(grown_texts(g), w, h)
    return built(a, g, places, moved(K.set_bounds(k, button_id(), places_button(places)), k), clicks, w, h)

# Accessors
# ---------

def size_of(m: Model) -> U32 & U32:
  Model{a, c, t, p, k, n, w, h} = m
  (w, h)

def kairo(m: Model) -> KT.State:
  Model{a, c, t, p, k, n, w, h} = m
  k

def clicks(m: Model) -> U32:
  Model{a, c, t, p, k, n, w, h} = m
  n

def with_kairo(m: Model, +k: KT.State) -> Model:
  Model{a, c, t, p, old, n, w, h} = m
  Model{a, c, t, p, k, n, w, h}

def glyphs(m: Model) -> U32:
  Model{a, c, t, p, k, n, w, h} = m
  U32.from_nat(List.length(&2, T.Glyph, c))

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

def rx(r: TG.Rect) -> F32:
  TG.Rect{x, y, w, h} = r
  x

def ry(r: TG.Rect) -> F32:
  TG.Rect{x, y, w, h} = r
  y

def frame(m: Model) -> S.Scene:
  Model{Assets{f, pic, heart}, cache, Texts{a, b, c, +d, e, pg, sv},
    Places{+panel, +ta, tb, tc, +bt, te, +pic_at, pic_cap, +svg_at, svg_cap}, k, n, +w, +h} = m
  s = S.new(w, h, 1.0, background())
  s = S.round_rect(s, crect(panel), 18.0, panel_color())
  s = S.border(s, crect(panel), 18.0, 1.0, line_color())
  s = S.fill_rect(s, G.Rect{rx(ta), (ry(ta) - 14.0 : F32), 64.0, 4.0}, accent())
  s = at(s, a, ta, ink())
  s = at(s, b, tb, muted())
  s = at(s, c, tc, ink())
  s = button(M.button(button_node(bt), k, metrics(d), 18.0, M.theme()), s, d)
  s = at(s, e, te, muted())
  s = Media.paint_picture(s, pic, rx(pic_at), ry(pic_at))
  s = at(s, pg, pic_cap, muted())
  s = Media.paint_svg(s, heart, rx(svg_at), ry(svg_at))
  at(s, sv, svg_cap, muted())
