import Base
import ../../scene.bend as S
import ../../../Runika/font.bend as F
import ../../../Syllo/main.bend as Sy
import ../../../Dithra/main.bend as D
import ../../../Dithra/raster.bend as R

# Text for the integrated demo: Syllo lays a string out, Dithra rasterizes
# each glyph once per size into a coverage mask kept in a cache, and runs
# become Chromi mask operations whose keys name (glyph, size), so the GPU
# atlas uploads every glyph once. Layout is redone when the text or its
# width changes; rasterization only for glyphs not seen before. A prepared
# run holds its glyphs already placed, so painting it is one Chromi
# operation per glyph and no lookup.

# A rasterized glyph: its offsets from the pen position on the baseline and
# its coverage, validated once as Chromi pixels.
type Glyph is Data:
  Glyph{key: U32, left: F32, top: F32, pixels: S.Pixels}

# A glyph of a run: its top-left corner relative to the run's top-left.
type Placed is Data:
  Placed{x: F32, y: F32, pixels: S.Pixels}

type Run is Data:
  Run{size: F32, width: F32, height: F32, ascent: F32, glyphs: List<&2, Placed>}

# (glyph, size) as an atlas key: size in quarter pixels above the glyph id.
def key(+gid: U32, +size: F32) -> U32:
  (1073741824 + (F32.to_u32(F32.round((size * 4.0 : F32))) << 16n) + gid : U32)

def entry.pick(hit: Bool, g: Glyph, later: Unit -> Maybe<&2, Glyph>) -> Maybe<&2, Glyph>:
  match hit:
    case True{}:
      Some{g}
    case False{}:
      later(Unit{})

# The cached glyph with key k; stops at the first match.
def entry(cache: List<&2, Glyph>, +k: U32) -> Maybe<&2, Glyph>:
  match cache:
    case Nil{}:
      None{}
    case Con{Glyph{+gk, ox, oy, p}, rest}:
      entry.pick(U32.is_eq(gk, k), Glyph{gk, ox, oy, p}, u => entry(rest, k))

def has.pick(hit: Bool, later: Unit -> Bool) -> Bool:
  match hit:
    case True{}:
      True{}
    case False{}:
      later(Unit{})

def has(cache: List<&2, Glyph>, +k: U32) -> Bool:
  match cache:
    case Nil{}:
      False{}
    case Con{Glyph{+gk, ox, oy, p}, rest}:
      has.pick(U32.is_eq(gk, k), u => has(rest, k))

def glyph.made(+k: U32, m: R.Mask) -> Result<&2, &2, String, Glyph>:
  R.Mask{+w, +h, +left, +top, adv, cov} = m
  do Result<&2, &2, String, Glyph>:
    p : S.Pixels <- S.coverage(k, w, h, cov)
    return Glyph{k, left, top, p}

def add(have: Bool, +font: F.Font, +gid: U32, +size: F32, cache: List<&2, Glyph>) ->
  Result<&2, &2, String, List<&2, Glyph>>:
  match have:
    case True{}:
      Done{cache}
    case False{}:
      do Result<&2, &2, String, List<&2, Glyph>>:
        m : R.Mask <- D.glyph(font, gid, size)
        g : Glyph <- glyph.made(key(gid, size), m)
        return g <> cache

# Rasterizes the glyphs of a run that the cache lacks.
def ensure(ps: List<&2, Sy.Placement>, +font: F.Font, +size: F32, +cache: List<&2, Glyph>) ->
  Result<&2, &2, String, List<&2, Glyph>>:
  match ps:
    case Nil{}:
      Done{cache}
    case Con{Sy.Placement{+gid, s, e, x, b, a, l}, rest}:
      do Result<&2, &2, String, List<&2, Glyph>>:
        +next : List<&2, Glyph> <- add(has(cache, key(gid, size)), font, gid, size, cache)
        ensure(rest, font, size, next)

def placements(layout: Sy.Layout) -> List<&2, Sy.Placement>:
  Sy.Layout{ps, w, h, asc, desc, lh, lines} = layout
  ps

def placed.one(m: Maybe<&2, Glyph>, +px: F32, +baseline: F32, rest: List<&2, Placed>) ->
  Result<&2, &2, String, List<&2, Placed>>:
  match m:
    case None{}:
      Fail{"demo text: glyph missing from the cache"}
    case Some{Glyph{k, +left, +top, p}}:
      Done{Placed{(F32.floor(px) + left : F32), (F32.floor(baseline) + top : F32), p} <> rest}

# Each placement's glyph from the cache, at its pen position.
def placed(ps: List<&2, Sy.Placement>, +cache: List<&2, Glyph>, +size: F32) ->
  Result<&2, &2, String, List<&2, Placed>>:
  match ps:
    case Nil{}:
      Done{Nil{}}
    case Con{Sy.Placement{+gid, st, en, +px, +baseline, adv, line}, rest}:
      do Result<&2, &2, String, List<&2, Placed>>:
        more : List<&2, Placed> <- placed(rest, cache, size)
        placed.one(entry(cache, key(gid, size)), px, baseline, more)

def run.of(layout: Sy.Layout, +size: F32, gs: List<&2, Placed>) -> Run:
  Sy.Layout{ps, w, h, asc, desc, lh, lines} = layout
  Run{size, w, h, asc, gs}

type Prepared is Data:
  Prepared{run: Run, cache: List<&2, Glyph>}

# Lays `text` out at `size` within `width`, makes sure every glyph is in
# the cache and places them. Answers the run and the grown cache.
def prepare(+font: F.Font, text: String, +size: F32, +width: F32, +cache: List<&2, Glyph>) ->
  Result<&2, &2, String, Prepared>:
  do Result<&2, &2, String, Prepared>:
    +layout : Sy.Layout <- Sy.layout(font, text, size, width)
    +grown : List<&2, Glyph> <- ensure(placements(layout), font, size, cache)
    gs : List<&2, Placed> <- placed(placements(layout), grown, size)
    return Prepared{run.of(layout, size, gs), grown}

def width(r: Run) -> F32:
  Run{s, w, h, a, ps} = r
  w

def height(r: Run) -> F32:
  Run{s, w, h, a, ps} = r
  h

def ascent(r: Run) -> F32:
  Run{s, w, h, a, ps} = r
  a

# Painting
# --------

def glyphs(gs: List<&2, Placed>, s: S.Scene, +x: F32, +top: F32, +color: U32) -> S.Scene:
  match gs:
    case Nil{}:
      s
    case Con{Placed{gx, gy, p}, rest}:
      glyphs(rest, S.draw(s, p, (x + gx : F32), (top + gy : F32), color), x, top, color)

# The run with its top-left corner at (x, top), in `color`.
def paint(s: S.Scene, r: Run, +x: F32, +top: F32, +color: U32) -> S.Scene:
  Run{size, w, h, a, gs} = r
  glyphs(gs, s, x, top, color)
