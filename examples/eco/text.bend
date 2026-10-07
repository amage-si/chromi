import Base
import ../../scene.bend as S
import ../../../Runika/font.bend as F
import ../../../Syllo/main.bend as Sy
import ../../../Dithra/main.bend as D
import ../../../Dithra/raster.bend as R
import ../../../Voltra/keys.bend as K

# Text for the integrated demo: Syllo lays a string out, Dithra rasterizes
# each glyph once per size into a coverage mask, and runs become Chromi
# mask operations whose keys name (glyph, size), so the GPU atlas uploads
# every glyph once. A prepared run holds its glyphs already placed, so
# painting it is one Chromi operation per glyph and no lookup.
#
# A Cache keeps the work of preparing text, so unchanged text costs almost
# nothing when a frame is rebuilt:
#   glyphs  (glyph, size) -> its mask, in a key map (Voltra's keys.bend);
#   runs    (text, size, width) -> its prepared run, in a key map from a
#           hash of the three to the runs with that hash. A hit compares
#           the text, size and width themselves, so a collision cannot
#           hand out another run.
# Runs live for two generations: when the newer one reaches `limit()`
# runs it becomes the older one and the previous older one is dropped;
# a hit in the older one copies the run back to the newer. A text that
# changes on every update (a counter) therefore cannot grow the cache
# without bound, while the texts a frame keeps using stay cached. A cache
# belongs to one font: preparing text in a font with another checksum
# starts from an empty cache. Glyph masks stay for the cache's life, as
# the GPU atlas keeps them.

# A rasterized glyph: its offsets from the pen position on the baseline and
# its coverage, validated once as Chromi pixels.
type Glyph is Data:
  Glyph{key: U32, left: F32, top: F32, pixels: S.Pixels}

# A glyph of a run: its top-left corner relative to the run's top-left.
type Placed is Data:
  Placed{x: F32, y: F32, pixels: S.Pixels}

type Run is Data:
  Run{size: F32, width: F32, height: F32, ascent: F32, glyphs: List<&2, Placed>}

# A prepared run under the text, size and width it was prepared for.
type Entry is Data:
  Entry{text: String, size: F32, width: F32, run: Run}

type Cache is Data:
  Cache{font: U32, glyphs: K.Keys<Glyph>, fresh: K.Keys<List<&2, Entry>>,
    stale: K.Keys<List<&2, Entry>>, count: U32}

type Prepared is Data:
  Prepared{run: Run, cache: Cache}

# Runs per generation.
def limit() -> U32:
  256

# An empty cache.
def cache() -> Cache:
  Cache{0, K.new(Glyph), K.new(List<&2, Entry>), K.new(List<&2, Entry>), 0}

# The glyph masks a cache holds.
def glyph_count(c: Cache) -> U32:
  Cache{f, gs, fresh, stale, n} = c
  K.size(Glyph, gs)

def runs.count(es: List<&2, List<&2, Entry>>, +acc: U32) -> U32:
  match es:
    case Nil{}:
      acc
    case Con{bucket, rest}:
      runs.count(rest, (acc + U32.from_nat(List.length(&2, Entry, bucket)) : U32))

# The runs a cache holds, both generations (a run in both counts twice).
def run_count(c: Cache) -> U32:
  Cache{f, gs, fresh, stale, n} = c
  (runs.count(K.values(List<&2, Entry>, fresh), 0) + runs.count(K.values(List<&2, Entry>, stale), 0) : U32)

# (glyph, size) as an atlas key: size in quarter pixels above the glyph id.
def key(+gid: U32, +size: F32) -> U32:
  (1073741824 + (F32.to_u32(F32.round((size * 4.0 : F32))) << 16n) + gid : U32)

# Run lookup
# ----------

def hash.text(s: String, +h: U32) -> U32:
  match s:
    case SNil{}:
      h
    case SCon{Chr{c}, rest}:
      hash.text(rest, ((h .^. c) * 16777619 : U32))

# FNV-1a over the text's scalars, then its size and width (quantized: equal
# floats hash alike, and a hit compares them exactly).
def hash(+text: String, +size: F32, +width: F32) -> U32:
  +h = hash.text(text, 2166136261)
  +a = ((h .^. F32.to_u32(F32.round((size * 64.0 : F32)))) * 16777619 : U32)
  ((a .^. F32.to_u32(F32.round((width * 8.0 : F32)))) * 16777619 : U32)

def find.pick(hit: Bool, +run: Run, later: Maybe<&2, Run>) -> Maybe<&2, Run>:
  match hit:
    case True{}:
      Some{run}
    case False{}:
      later

def find.bucket(es: List<&2, Entry>, +text: String, +size: F32, +width: F32) -> Maybe<&2, Run>:
  match es:
    case Nil{}:
      None{}
    case Con{Entry{t, s, w, +r}, rest}:
      find.pick(F32.is_eq(s, size) && F32.is_eq(w, width) && String.eq(t, text), r,
        find.bucket(rest, text, size, width))

def find.in(m: Maybe<&2, List<&2, Entry>>, +text: String, +size: F32, +width: F32) -> Maybe<&2, Run>:
  match m:
    case None{}:
      None{}
    case Some{es}:
      find.bucket(es, text, size, width)

def find(runs: K.Keys<List<&2, Entry>>, +h: U32, +text: String, +size: F32, +width: F32) -> Maybe<&2, Run>:
  find.in(K.get(List<&2, Entry>, runs, h), text, size, width)

def bucket(+runs: K.Keys<List<&2, Entry>>, +h: U32) -> List<&2, Entry>:
  Maybe.default(&2, List<&2, Entry>, K.get(List<&2, Entry>, runs, h), Nil{})

def remember.rotate(full: Bool, +f: U32, gs: K.Keys<Glyph>, fresh: K.Keys<List<&2, Entry>>,
  stale: K.Keys<List<&2, Entry>>, +n: U32) -> Cache:
  match full:
    case True{}:
      Cache{f, gs, K.new(List<&2, Entry>), fresh, 0}
    case False{}:
      Cache{f, gs, fresh, stale, n}

# The cache with a run added to the newer generation.
def remember(c: Cache, +h: U32, e: Entry) -> Cache:
  Cache{+f, gs, +fresh, stale, +n} = c
  remember.rotate(U32.is_ge((n + 1 : U32), limit()), f, gs,
    K.put(List<&2, Entry>, fresh, h, e <> bucket(fresh, h)), stale, (n + 1 : U32))

def for_font.pick(same: Bool, c: Cache, +sum: U32) -> Cache:
  match same:
    case True{}:
      c
    case False{}:
      Cache{sum, K.new(Glyph), K.new(List<&2, Entry>), K.new(List<&2, Entry>), 0}

# The cache if it belongs to the font with this checksum, else an empty one
# for that font.
def for_font(c: Cache, +sum: U32) -> Cache:
  Cache{+f, gs, fresh, stale, n} = c
  for_font.pick(U32.is_eq(f, sum), Cache{f, gs, fresh, stale, n}, sum)

def glyphs_of(c: Cache) -> K.Keys<Glyph>:
  Cache{f, gs, fresh, stale, n} = c
  gs

def fresh_of(c: Cache) -> K.Keys<List<&2, Entry>>:
  Cache{f, gs, fresh, stale, n} = c
  fresh

def stale_of(c: Cache) -> K.Keys<List<&2, Entry>>:
  Cache{f, gs, fresh, stale, n} = c
  stale

def with_glyphs(c: Cache, gs: K.Keys<Glyph>) -> Cache:
  Cache{f, old, fresh, stale, n} = c
  Cache{f, gs, fresh, stale, n}

# Preparing a run
# ---------------

def glyph.made(+k: U32, m: R.Mask) -> Result<&2, &2, String, Glyph>:
  R.Mask{+w, +h, +left, +top, adv, cov} = m
  do Result<&2, &2, String, Glyph>:
    p : S.Pixels <- S.coverage(k, w, h, cov)
    return Glyph{k, left, top, p}

type Got is Data:
  Got{glyph: Glyph, glyphs: K.Keys<Glyph>}

def got.new(r: Result<&2, &2, String, Glyph>, +k: U32, gs: K.Keys<Glyph>) -> Result<&2, &2, String, Got>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{+g}:
      Done{Got{g, K.put(Glyph, gs, k, g)}}

def got.mask(r: Result<&2, &2, String, R.Mask>, +k: U32, gs: K.Keys<Glyph>) -> Result<&2, &2, String, Got>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{m}:
      got.new(glyph.made(k, m), k, gs)

# The glyph's mask from the cache, or rasterized and added to it.
def got(m: Maybe<&2, Glyph>, +font: F.Font, +gid: U32, +size: F32, gs: K.Keys<Glyph>) -> Result<&2, &2, String, Got>:
  match m:
    case Some{g}:
      Done{Got{g, gs}}
    case None{}:
      got.mask(D.glyph(font, gid, size), key(gid, size), gs)

type Acc is Data:
  Acc{glyphs: K.Keys<Glyph>, placed: List<&2, Placed>}

def placed.step(r: Result<&2, &2, String, Got>, +px: F32, +baseline: F32, acc: List<&2, Placed>) ->
  Result<&2, &2, String, Acc>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{Got{Glyph{k, +left, +top, p}, gs}}:
      Done{Acc{gs, Placed{(F32.floor(px) + left : F32), (F32.floor(baseline) + top : F32), p} <> acc}}

type Made is Data:
  Made{placed: List<&2, Placed>, glyphs: K.Keys<Glyph>}

# Each placement's glyph at its pen position, rasterizing the glyphs the
# cache lacks; `state` holds the cache and the glyphs placed so far.
def placed(ps: List<&2, Sy.Placement>, +font: F.Font, +size: F32, state: Result<&2, &2, String, Acc>) ->
  Result<&2, &2, String, Made>:
  match ps state:
    case _ Fail{e}:
      Fail{e}
    case Nil{} Done{Acc{gs, acc}}:
      Done{Made{List.reverse(&2, Placed, acc), gs}}
    case Con{Sy.Placement{+gid, from, to, +px, +baseline, adv, line}, rest} Done{Acc{+gs, acc}}:
      placed(rest, font, size, placed.step(got(K.get(Glyph, gs, key(gid, size)), font, gid, size, gs), px, baseline, acc))

def placements(layout: Sy.Layout) -> List<&2, Sy.Placement>:
  Sy.Layout{ps, w, h, asc, desc, lh, lines} = layout
  ps

def run.of(layout: Sy.Layout, +size: F32, gs: List<&2, Placed>) -> Run:
  Sy.Layout{ps, w, h, asc, desc, lh, lines} = layout
  Run{size, w, h, asc, gs}

type Fresh is Data:
  Fresh{run: Run, glyphs: K.Keys<Glyph>}

def make.placed(r: Result<&2, &2, String, Made>, layout: Sy.Layout, +size: F32) -> Result<&2, &2, String, Fresh>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{Made{ps, gs}}:
      Done{Fresh{run.of(layout, size, ps), gs}}

def make.laid(r: Result<&2, &2, String, Sy.Layout>, +font: F.Font, +size: F32, gs: K.Keys<Glyph>) ->
  Result<&2, &2, String, Fresh>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{+layout}:
      make.placed(placed(placements(layout), font, size, Done{Acc{gs, Nil{}}}), layout, size)

# A run prepared from scratch (only its glyph masks may come from `gs`).
def make(+font: F.Font, text: String, +size: F32, +width: F32, gs: K.Keys<Glyph>) -> Result<&2, &2, String, Fresh>:
  make.laid(Sy.layout(font, text, size, width), font, size, gs)

def prepare.made(r: Result<&2, &2, String, Fresh>, c: Cache, +h: U32, +text: String, +size: F32, +width: F32) ->
  Result<&2, &2, String, Prepared>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{Fresh{+run, gs}}:
      Done{Prepared{run, remember(with_glyphs(c, gs), h, Entry{text, size, width, run})}}

def prepare.stale(m: Maybe<&2, Run>, +c: Cache, +font: F.Font, +text: String, +size: F32, +width: F32, +h: U32) ->
  Result<&2, &2, String, Prepared>:
  match m:
    case Some{+run}:
      Done{Prepared{run, remember(c, h, Entry{text, size, width, run})}}
    case None{}:
      prepare.made(make(font, text, size, width, glyphs_of(c)), c, h, text, size, width)

def prepare.fresh(m: Maybe<&2, Run>, +c: Cache, +font: F.Font, +text: String, +size: F32, +width: F32, +h: U32) ->
  Result<&2, &2, String, Prepared>:
  match m:
    case Some{run}:
      Done{Prepared{run, c}}
    case None{}:
      prepare.stale(find(stale_of(c), h, text, size, width), c, font, text, size, width, h)

def prepare.in(+c: Cache, +font: F.Font, +text: String, +size: F32, +width: F32) -> Result<&2, &2, String, Prepared>:
  +h = hash(text, size, width)
  prepare.fresh(find(fresh_of(c), h, text, size, width), c, font, text, size, width, h)

# Lays `text` out at `size` within `width` and places its glyphs, or takes
# the run from the cache when this text, size and width were prepared
# before. Answers the run and the cache that now holds it.
def prepare(+font: F.Font, text: String, +size: F32, +width: F32, cache: Cache) -> Result<&2, &2, String, Prepared>:
  prepare.in(for_font(cache, F.checksum(font)), font, text, size, width)

def run_of_fresh(r: Result<&2, &2, String, Fresh>) -> Result<&2, &2, String, Run>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{Fresh{run, gs}}:
      Done{run}

# The run prepared from scratch, ignoring and leaving every cache: the
# reference the cached path must equal.
def prepare_uncached(+font: F.Font, text: String, +size: F32, +width: F32) -> Result<&2, &2, String, Run>:
  run_of_fresh(make(font, text, size, width, K.new(Glyph)))

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
