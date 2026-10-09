import Base
import ./geometry.bend as G
import ./scene.bend as S
import ../Voltra/gpu.bend as V
import ../Voltra/quads.bend as Q
import ../Voltra/atlas.bend as At
import ../Voltra/commands.bend as VC
import ../Voltra/words.bend as W
import ./frame.bend as F

# Chromi's GPU path: a draw list (scene.bend) rendered by Voltra.
#
# Each operation becomes one Voltra quad: fills as flat quads, rounded
# boxes and rings as Voltra's antialiased kinds, bitmaps as texel quads and
# masks as coverage quads, each with the operation's clip box. Bitmaps and
# masks live in one atlas texture, uploaded once per key: a frame uploads
# only pixels the atlas has not seen (new glyphs, new images), in one
# transfer, then draws everything in one instanced draw call. When the
# atlas is full it starts over with what the current frame needs.
#
# Voltra's shader computes every value with the integer rules the CPU
# reference (replay.bend) uses, so both produce the same bytes; gpu_tests
# compare them pixel by pixel.

def atlas_size() -> U32:
  1024

# `quads` and `partial` describe the last frame drawn by `render` (how many
# quads it uploaded and drew, and whether it redrew only its damage); a
# frame drawn with `draw` leaves 0 and False.
type Renderer is Data:
  Renderer{gpu: V.Gpu, atlas: At.Atlas, uploaded: U32, resets: U32, quads: U32, partial: Bool}

def ready(+g: V.Gpu) -> IO(Renderer):
  do IO<Renderer>:
    +g1 : V.Gpu <- V.blank(g, atlas_size(), atlas_size())
    return Renderer{g1, At.new(atlas_size(), atlas_size()), 0, 0, 0, False{}}

# A renderer presenting into the native window Ankra hands over.
def open(+native: List<&2, U32>, +w: U32, +h: U32, +vsync: Bool) -> IO(Renderer):
  do IO<Renderer>:
    +g : V.Gpu <- V.open(native, w, h, vsync)
    ready(g)

# A renderer drawing into a w x h offscreen image (see `read`).
def open_offscreen(+w: U32, +h: U32) -> IO(Renderer):
  do IO<Renderer>:
    +g : V.Gpu <- V.open_offscreen(w, h)
    ready(g)

def gpu(r: Renderer) -> V.Gpu:
  Renderer{g, a, u, n, q, pt} = r
  g

def with_gpu(r: Renderer, +g: V.Gpu) -> Renderer:
  Renderer{old, a, u, n, q, pt} = r
  Renderer{g, a, u, n, q, pt}

# Texels uploaded to the atlas so far, and how often it started over.
def uploaded(r: Renderer) -> U32:
  Renderer{g, a, u, n, q, pt} = r
  u

def resets(r: Renderer) -> U32:
  Renderer{g, a, u, n, q, pt} = r
  n

def last_quads(r: Renderer) -> U32:
  Renderer{g, a, u, n, q, pt} = r
  q

def last_partial(r: Renderer) -> Bool:
  Renderer{g, a, u, n, q, pt} = r
  pt

def entries(r: Renderer) -> U32:
  Renderer{g, a, u, n, q, pt} = r
  At.count(a)

def pending(r: Renderer) -> Bool:
  V.pending(gpu(r))

def invalidate(r: Renderer) -> Renderer:
  Renderer{g, a, u, n, q, pt} = r
  Renderer{V.invalidate(g), a, u, n, q, pt}

def target_size(r: Renderer) -> V.Size:
  V.target_size(gpu(r))

# Records a new window size; rebuilds the swapchain when it changed.
def resize(+r: Renderer, +w: U32, +h: U32) -> IO(Renderer):
  do IO<Renderer>:
    +g : V.Gpu <- V.resize(gpu(r), w, h)
    return with_gpu(r, g)

def close(r: Renderer) -> IO(V.Report):
  V.close(gpu(r))

# Planning (pure)
# ---------------

type Plan is Data:
  Plan{atlas: At.Atlas, regions: List<&2, V.Region>, quads: List<&2, Q.Quad>,
    texels: U32, full: Bool}

def clip(q: Q.Quad, box: G.Box) -> Q.Quad:
  G.Box{x0, y0, x1, y1} = box
  Q.clipped(q, x0, y0, x1, y1)

# Coverage c is stored in the red channel the shader reads (the rest of
# the texel repeats it, which keeps atlas dumps readable).
def mask_words(cs: List<&2, U32>) -> List<&2, U32>:
  match cs:
    case Nil{}:
      Nil{}
    case Con{+c, rest}:
      ((c << 24n) .|. (c << 16n) .|. (c << 8n) .|. 255 : U32) <> mask_words(rest)

def texel_words(mask: Bool, data: List<&2, U32>) -> List<&2, U32>:
  match mask:
    case True{}:
      mask_words(data)
    case False{}:
      data

def textured.quad(mask: Bool, +x: U32, +y: U32, +w: U32, +h: U32, +u: U32, +v: U32,
  +ink: U32, box: G.Box) -> Q.Quad:
  match mask:
    case True{}:
      clip(Q.mask(x, y, w, h, u, v, ink), box)
    case False{}:
      clip(Q.image(x, y, w, h, u, v, w, h, 4294967295), box)

type Item is Data:
  Item{key: U32, x: U32, y: U32, width: U32, height: U32, data: List<&2, U32>,
    mask: Bool, ink: U32, clip: G.Box}

def textured.room(m: Maybe<&2, At.Entry>, a: At.Atlas, it: Item, rs: List<&2, V.Region>,
  qs: List<&2, Q.Quad>, +texels: U32, +full: Bool) -> Plan:
  match m:
    case None{}:
      Plan{a, rs, qs, texels, True{}}
    case Some{At.Entry{ek, +u, +v, ew, eh}}:
      Item{k, +x, +y, +w, +h, data, +mask, +ink, box} = it
      Plan{a, V.Region{u, v, w, h, texel_words(mask, data)} <> rs,
        textured.quad(mask, x, y, w, h, u, v, ink, box) <> qs, (texels + w * h : U32), full}

def textured.placed(r: At.Atlas & Maybe<&2, At.Entry>, it: Item, rs: List<&2, V.Region>,
  qs: List<&2, Q.Quad>, +texels: U32, +full: Bool) -> Plan:
  (a, m) = r
  textured.room(m, a, it, rs, qs, texels, full)

def textured.found(m: Maybe<&2, At.Entry>, a: At.Atlas, +it: Item, rs: List<&2, V.Region>,
  qs: List<&2, Q.Quad>, +texels: U32, +full: Bool, +k: U32, +w: U32, +h: U32) -> Plan:
  match m:
    case Some{At.Entry{ek, +u, +v, ew, eh}}:
      Item{ik, +x, +y, iw, ih, data, +mask, +ink, box} = it
      Plan{a, rs, textured.quad(mask, x, y, w, h, u, v, ink, box) <> qs, texels, full}
    case None{}:
      textured.placed(At.place(a, k, w, h), it, rs, qs, texels, full)

def textured(p: Plan, +it: Item) -> Plan:
  Plan{+a, rs, qs, texels, full} = p
  Item{+k, x, y, +w, +h, data, mask, ink, box} = it
  textured.found(At.lookup(a, k), a, it, rs, qs, texels, full, k, w, h)

def round.quad(ring: Bool, +x0: U32, +y0: U32, +x1: U32, +y1: U32, +r: U32, +b: U32,
  +color: U32) -> Q.Quad:
  match ring:
    case True{}:
      Q.ring(x0, y0, x1, y1, r, b, color)
    case False{}:
      Q.rounded(x0, y0, x1, y1, r, color)

def with_quad(p: Plan, q: Q.Quad) -> Plan:
  Plan{a, rs, qs, t, f} = p
  Plan{a, rs, q <> qs, t, f}

def step(p: Plan, o: S.Op) -> Plan:
  match o:
    case S.Fill{G.Box{+x0, +y0, +x1, +y1}, color}:
      with_quad(p, Q.fill(x0, y0, (x1 - x0 : U32), (y1 - y0 : U32), color))
    case S.Round{x0, y0, x1, y1, r, +b, color, box}:
      with_quad(p, clip(round.quad(U32.is_ne(b, 0), x0, y0, x1, y1, r, b, color), box))
    case S.Bitmap{key, x, y, w, h, data, box}:
      textured(p, Item{key, x, y, w, h, data, False{}, 0, box})
    case S.Mask{key, x, y, w, h, data, ink, box}:
      textured(p, Item{key, x, y, w, h, data, True{}, ink, box})

def plan.go(os: List<&2, S.Op>, p: Plan) -> Plan:
  match os:
    case Nil{}:
      p
    case o <> rest:
      plan.go(rest, step(p, o))

# The quads of a draw list in order, the atlas rectangles to upload first,
# and whether some bitmap or mask found no room.
def planned(p: Plan) -> Plan:
  Plan{a, rs, qs, t, f} = p
  Plan{a, List.reverse(&2, V.Region, rs), List.reverse(&2, Q.Quad, qs), t, f}

def plan(os: List<&2, S.Op>, a: At.Atlas) -> Plan:
  planned(plan.go(os, Plan{a, Nil{}, Nil{}, 0, False{}}))

def full(p: Plan) -> Bool:
  Plan{a, rs, qs, t, f} = p
  f

# Drawing
# -------

def submit(r: Renderer, p: Plan, +clear: U32, +reset: Bool) -> IO(Renderer):
  Renderer{g, old, +u, +n, q, pt} = r
  Plan{a, rs, qs, +t, f} = p
  do IO<Renderer>:
    +g1 : V.Gpu <- V.update(g, rs)
    +g2 : V.Gpu <- V.draw(g1, qs, clear)
    return Renderer{g2, a, (u + t : U32), (n + Bool.to_u32(reset) : U32), 0, False{}}

def draw.planned(overflow: Bool, +r: Renderer, +os: List<&2, S.Op>, p: Plan, +clear: U32) -> IO(Renderer):
  match overflow:
    case False{}:
      submit(r, p, clear, False{})
    case True{}:
      # Start the atlas over with only what this frame needs.
      Renderer{g, a, u, n, q, pt} = r
      submit(r, plan(os, At.reset(a)), clear, True{})

def draw.ops(res: Result<&1, &1, U32 & String, List<&2, S.Op>>, +r: Renderer, +clear: U32) -> IO(Renderer):
  match res:
    case Fail{(code, message)}:
      IO.die(Renderer, code, message)
    case Done{+os}:
      Renderer{g, +a, u, n, q, pt} = r
      +p = plan(os, a)
      draw.planned(full(p), r, os, p, clear)

# Draws the scene and presents it (or keeps it for `read`, offscreen). A
# failed scene ends the program with its error.
def draw(+r: Renderer, +s: S.Scene) -> IO(Renderer):
  draw.ops(S.ops(s), r, S.background(s))

def read.done(r: Renderer, got: V.Gpu & Array<U32>) -> Renderer & Array<U32>:
  (g, px) = got
  (with_gpu(r, g), px)

# The last offscreen frame as row-major 0xRRGGBBAA words.
def read(+r: Renderer) -> IO(Renderer & Array<U32>):
  do IO<Renderer & Array<U32>>:
    got : V.Gpu & Array<U32> <- V.read(gpu(r))
    return read.done(r, got)

# Retained frames
# ---------------
#
# `render` draws a retained frame (frame.bend) on Voltra's canvas, which
# keeps the last picture: only the damaged boxes are redrawn, each with the
# background and the quads of every part that meets it, scissored to the
# box (Voltra's `paint`). A part's quads are planned (atlas placed) when it
# is first drawn and written once into Voltra's store, which keeps them on
# the GPU; the part keeps where they lie. A kept part costs nothing more:
# no atlas lookup, no packing, no copy, only a run of stored instances in
# the boxes it meets (adjacent parts' runs join into one draw). The store
# only grows: when a frame's new quads do not fit, it starts over (Voltra
# waits for the device) and the frame plans again every part it draws.
# A frame is drawn whole when it asks for it (the first frame, a new
# surface), when the canvas does not hold the last picture of this surface
# (a new swapchain, a minimized window), or when its damage covers more
# than half of the surface. A frame's planned parts belong to the renderer
# that drew it.

# Parts' quads belong to one atlas and one store: the epoch counts the
# fresh starts of both.
def epoch(+resets: U32, +generation: U32) -> U32:
  (resets + generation + 1 : U32)

# A frame's planning: the plan (atlas, regions to upload, texels), its
# parts (reversed), the quads it planned for the store (reversed), how many
# of those, and how many quads the parts it draws have in all.
type Prep is Data:
  Prep{plan: Plan, parts: List<&2, F.Part>, fresh: List<&2, Q.Quad>, count: U32, drawn: U32}

def stale(c: F.Cache, +epoch: U32) -> Bool:
  match c:
    case F.Unplanned{}:
      True{}
    case F.Planned{e, n, first}:
      U32.is_ne(e, epoch)

def quads.of(c: F.Cache) -> U32:
  match c:
    case F.Unplanned{}:
      0
    case F.Planned{e, n, first}:
      n

def fresh(p: Plan) -> Plan:
  Plan{a, rs, qs, t, f} = p
  Plan{a, rs, Nil{}, t, f}

# The part's quads (`qs`, reversed) go to the store after those planned so
# far, from index base + count on.
def prepare.planned(p: Plan, +part: F.Part, +epoch: U32, +base: U32, acc: Prep) -> Prep:
  Plan{a, rs, +qs, t, f} = p
  Prep{old, ps, more, +count, +drawn} = acc
  +n = U32.from_nat(List.length(&2, Q.Quad, qs))
  Prep{Plan{a, rs, Nil{}, t, f}, F.part.cached(part, F.Planned{epoch, n, (base + count : U32)}) <> ps,
    List.append(&2, Q.Quad, qs, more), (count + n : U32), (drawn + n : U32)}

def prepare.plan(acc: Prep) -> Plan:
  Prep{p, ps, more, count, drawn} = acc
  fresh(p)

def prepare.step(hit: Bool, old: Bool, +part: F.Part, +epoch: U32, +base: U32, +acc: Prep) -> Prep:
  match hit old:
    case True{} True{}:
      prepare.planned(plan.go(F.part.ops(part), prepare.plan(acc)), part, epoch, base, acc)
    case True{} False{}:
      Prep{p, ps, more, count, +drawn} = acc
      Prep{p, part <> ps, more, count, (drawn + quads.of(F.part.cache(part)) : U32)}
    case False{} _:
      Prep{p, ps, more, count, drawn} = acc
      Prep{p, part <> ps, more, count, drawn}

# Plans the parts this frame draws (every part when whole, else those that
# meet a region) whose quads are not of this epoch, for the store from
# index `base` on. Parts come out reversed.
def prepare(ps: List<&2, F.Part>, +regions: List<&2, G.Box>, +whole: Bool, +epoch: U32, +base: U32,
  acc: Prep) -> Prep:
  match ps:
    case Nil{}:
      acc
    case Con{+part, rest}:
      prepare(rest, regions, whole, epoch, base, prepare.step(whole || F.touched(regions, F.part.bounds(part)),
        stale(F.part.cache(part), epoch), part, epoch, base, acc))

def prep.start(a: At.Atlas) -> Prep:
  Prep{Plan{a, Nil{}, Nil{}, 0, False{}}, Nil{}, Nil{}, 0, 0}

def prep.full(p: Prep) -> Bool:
  Prep{plan, ps, more, count, drawn} = p
  full(plan)

def prep.parts(p: Prep) -> List<&2, F.Part>:
  Prep{plan, ps, more, count, drawn} = p
  List.reverse(&2, F.Part, ps)

def prep.count(p: Prep) -> U32:
  Prep{plan, ps, more, count, drawn} = p
  count

def prep.drawn(p: Prep) -> U32:
  Prep{plan, ps, more, count, drawn} = p
  drawn

# The same atlas, regions and texels, nothing planned for the store yet.
def prep.again(p: Prep) -> Prep:
  Prep{plan, ps, more, count, drawn} = p
  Prep{fresh(plan), Nil{}, Nil{}, 0, 0}

# Runs of stored instances
# ------------------------

def runs.joined(join: Bool, +s: Bool, +f: U32, +k: U32, rest: List<&2, VC.Run>, +first: U32, +n: U32) ->
  List<&2, VC.Run>:
  match join:
    case True{}:
      VC.Run{True{}, f, (k + n : U32)} <> rest
    case False{}:
      VC.Run{True{}, first, n} <> VC.Run{s, f, k} <> rest

# A stored run after the last ones (reversed), joined with the last when
# they touch.
def runs.add(acc: List<&2, VC.Run>, +first: U32, +n: U32) -> List<&2, VC.Run>:
  match acc:
    case Nil{}:
      [VC.Run{True{}, first, n}]
    case Con{VC.Run{+s, +f, +k}, rest}:
      runs.joined(s && U32.is_eq((f + k : U32), first), s, f, k, rest, first, n)

def runs.some(empty: Bool, acc: List<&2, VC.Run>, +first: U32, +n: U32) -> List<&2, VC.Run>:
  match empty:
    case True{}:
      acc
    case False{}:
      runs.add(acc, first, n)

def runs.part(hit: Bool, c: F.Cache, acc: List<&2, VC.Run>) -> List<&2, VC.Run>:
  match hit c:
    case True{} F.Planned{e, +n, +first}:
      runs.some(U32.is_eq(n, 0), acc, first, n)
    case _ _:
      acc

# The stored quads of the parts that meet the box (all when `every`), in
# order, as runs.
def runs.of(ps: List<&2, F.Part>, +box: G.Box, +every: Bool, acc: List<&2, VC.Run>) -> List<&2, VC.Run>:
  match ps:
    case Nil{}:
      List.reverse(&2, VC.Run, acc)
    case Con{F.Part{id, st, +b, os, c}, rest}:
      runs.of(rest, box, every, runs.part(every || G.meet(b, box), c, acc))

def runs.total(rs: List<&2, VC.Run>, +acc: U32) -> U32:
  match rs:
    case Nil{}:
      acc
    case Con{VC.Run{s, f, n}, rest}:
      runs.total(rest, (acc + n : U32))

def ranges.total(rs: List<&2, VC.Range>, +acc: U32) -> U32:
  match rs:
    case Nil{}:
      acc
    case Con{VC.Range{x, y, w, h, first, n}, rest}:
      ranges.total(rest, (acc + n : U32))
    case Con{VC.Spans{x, y, w, h, runs}, rest}:
      ranges.total(rest, runs.total(runs, acc))

# One range per region: its background quad (the frame's instance k), then
# the stored quads of the parts that meet it.
def ranges.of(rs: List<&2, G.Box>, +ps: List<&2, F.Part>, +k: U32) -> List<&2, VC.Range>:
  match rs:
    case Nil{}:
      Nil{}
    case Con{G.Box{+x0, +y0, +x1, +y1}, rest}:
      VC.Spans{x0, y0, (x1 - x0 : U32), (y1 - y0 : U32),
        VC.Run{False{}, k, 1} <> runs.of(ps, G.Box{x0, y0, x1, y1}, False{}, Nil{})} <>
        ranges.of(rest, ps, (k + 1 : U32))

def ranges.pick(whole: Bool, +regions: List<&2, G.Box>, +ps: List<&2, F.Part>, +w: U32, +h: U32) ->
  List<&2, VC.Range>:
  match whole:
    case True{}:
      [VC.Spans{0, 0, w, h, runs.of(ps, G.Box{0, 0, 0, 0}, True{}, Nil{})}]
    case False{}:
      ranges.of(regions, ps, 0)

# The background quads of a partial frame, one per region (a whole frame
# clears the canvas instead).
def backgrounds(rs: List<&2, G.Box>, +bg: U32) -> List<&2, Q.Quad>:
  match rs:
    case Nil{}:
      Nil{}
    case Con{G.Box{+x0, +y0, +x1, +y1}, rest}:
      Q.fill(x0, y0, (x1 - x0 : U32), (y1 - y0 : U32), bg) <> backgrounds(rest, bg)

def backgrounds.pick(whole: Bool, +regions: List<&2, G.Box>, +bg: U32) -> List<&2, Q.Quad>:
  match whole:
    case True{}:
      Nil{}
    case False{}:
      backgrounds(regions, bg)

# Rendering
# ---------

def extent.w(s: V.Size) -> U32:
  V.Size{w, h} = s
  w

def extent.h(s: V.Size) -> U32:
  V.Size{w, h} = s
  h

def paint.words(+g: V.Gpu, ws: Array<U32> & U32, +bg: U32, ranges: List<&2, VC.Range>, +whole: Bool,
  rs: List<&2, V.Region>) -> IO(V.Gpu):
  (a, +n) = ws
  V.paint(g, a, n, bg, ranges, whole, rs)

def render.paint(+r: Renderer, prep: Prep, +reset: Bool, +whole: Bool, +regions: List<&2, G.Box>,
  +w: U32, +h: U32, +sc: F32, +bg: U32) -> IO(Renderer & F.Frame):
  Renderer{g, a0, +u, +n, q, pt} = r
  Prep{p, back, more, count, drawn} = prep
  Plan{a, rs, qs, +t, f} = p
  +ps = List.reverse(&2, F.Part, back)
  +ext = V.target_size(g)
  +ranges = ranges.pick(whole, regions, ps, U32.min(w, extent.w(ext)), U32.min(h, extent.h(ext)))
  do IO<Renderer & F.Frame>:
    +g2 : V.Gpu <- paint.words(g, Q.words(backgrounds.pick(whole, regions, bg)), bg, ranges, whole, rs)
    return (Renderer{g2, a, (u + t : U32), (n + Bool.to_u32(reset) : U32), ranges.total(ranges, 0),
      Bool.not(whole)}, F.Frame{w, h, sc, bg, ps, Nil{}, False{}})

def store.words(+g: V.Gpu, ws: Array<U32> & U32) -> IO(V.Gpu & U32):
  (a, +n) = ws
  V.store(g, a, n)

def render.stored(r: Renderer, got: V.Gpu & U32) -> Renderer:
  (+g, first) = got
  with_gpu(r, g)

# Writes the frame's new quads into the store, then paints.
def render.store(+r: Renderer, prep: Prep, +reset: Bool, +whole: Bool, +regions: List<&2, G.Box>,
  +w: U32, +h: U32, +sc: F32, +bg: U32) -> IO(Renderer & F.Frame):
  Prep{p, back, more, count, drawn} = prep
  do IO<Renderer & F.Frame>:
    got : V.Gpu & U32 <- store.words(gpu(r), Q.words(List.reverse(&2, Q.Quad, more)))
    render.paint(render.stored(r, got), Prep{p, back, Nil{}, count, drawn}, reset, whole, regions, w, h,
      sc, bg)

# When the frame's new quads do not fit, the store starts over with room
# for every quad the frame draws, and the frame plans those parts again
# (same atlas: no new uploads) for the empty store.
def render.room(fits: Bool, +r: Renderer, +prep: Prep, +reset: Bool, +whole: Bool,
  +regions: List<&2, G.Box>, +w: U32, +h: U32, +sc: F32, +bg: U32) -> IO(Renderer & F.Frame):
  match fits:
    case True{}:
      render.store(r, prep, reset, whole, regions, w, h, sc, bg)
    case False{}:
      Renderer{g, a, u, +n, q, pt} = r
      do IO<Renderer & F.Frame>:
        +g1 : V.Gpu <- V.store_restart(g, prep.drawn(prep))
        render.store(with_gpu(r, g1), prepare(prep.parts(prep), regions, whole,
          epoch((n + Bool.to_u32(reset) : U32), V.store_generation(g1)), 0, prep.again(prep)), reset, whole,
          regions, w, h, sc, bg)

def render.fit(+r: Renderer, +prep: Prep, +reset: Bool, +whole: Bool, +regions: List<&2, G.Box>,
  +w: U32, +h: U32, +sc: F32, +bg: U32) -> IO(Renderer & F.Frame):
  render.room(V.store_room(gpu(r), prep.count(prep)), r, prep, reset, whole, regions, w, h, sc, bg)

def render.planned(overflow: Bool, +r: Renderer, +prep: Prep, +whole: Bool,
  +regions: List<&2, G.Box>, +w: U32, +h: U32, +sc: F32, +bg: U32) -> IO(Renderer & F.Frame):
  match overflow:
    case False{}:
      render.fit(r, prep, False{}, whole, regions, w, h, sc, bg)
    case True{}:
      # The atlas starts over with what this frame draws; every other part
      # is planned again when it is next drawn.
      Renderer{g, a, u, +n, q, pt} = r
      render.fit(r, prepare(prep.parts(prep), regions, whole, epoch((n + 1 : U32), V.store_generation(g)),
        V.stored(g), prep.start(At.reset(a))), True{}, whole, regions, w, h, sc, bg)

def render.go(+whole: Bool, +r: Renderer, ps: List<&2, F.Part>, +regions: List<&2, G.Box>,
  +w: U32, +h: U32, +sc: F32, +bg: U32) -> IO(Renderer & F.Frame):
  Renderer{+g, +a, u, +n, q, pt} = r
  +prep = prepare(ps, regions, whole, epoch(n, V.store_generation(g)), V.stored(g), prep.start(a))
  render.planned(prep.full(prep), r, prep, whole, regions, w, h, sc, bg)

def size.differs(s: V.Size, +w: U32, +h: U32) -> Bool:
  V.Size{+tw, +th} = s
  U32.is_ne(tw, w) || U32.is_ne(th, h)

def render.whole(+r: Renderer, +asked: Bool, +w: U32, +h: U32, +regions: List<&2, G.Box>) -> Bool:
  asked || Bool.not(V.kept(gpu(r))) || size.differs(V.target_size(gpu(r)), w, h) ||
    U32.is_gt((F.area(regions, 0) * 2 : U32), (w * h : U32))

# A partial frame with no damage changes no pixel: the canvas and the image
# on screen already show it. Unless the GPU owes a frame (a rebuilt
# swapchain), it is neither painted nor presented: no quads, no uploads,
# no submit. The frames in flight are untouched (nothing is acquired or
# waited for), and the next paint copies the whole canvas into the image
# it acquires, so a skipped present loses nothing.
def render.still(+whole: Bool, regions: List<&2, G.Box>, r: Renderer) -> Bool:
  Bool.not(whole) && List.is_empty(&2, G.Box, regions) && Bool.not(pending(r))

# The renderer and frame a skipped paint answers: those a paint of no
# regions would (every part kept as it was planned, 0 quads, partial).
def render.skipped(r: Renderer, f: F.Frame) -> IO(Renderer & F.Frame):
  Renderer{g, a, u, n, q, pt} = r
  IO.pure(Renderer & F.Frame, (Renderer{g, a, u, n, 0, True{}}, f))

def render.at(still: Bool, +whole: Bool, +r: Renderer, ps: List<&2, F.Part>, +regions: List<&2, G.Box>,
  +w: U32, +h: U32, +sc: F32, +bg: U32) -> IO(Renderer & F.Frame):
  match still:
    case True{}:
      render.skipped(r, F.Frame{w, h, sc, bg, ps, Nil{}, False{}})
    case False{}:
      render.go(whole, r, ps, regions, w, h, sc, bg)

# Draws a retained frame and answers it as drawn: its parts with where
# their quads lie in the store, for the next frame to keep, and no damage
# left. A failed frame ends the program with its error. A frame with no
# damage is not painted or presented (`render.still`).
def render(+r: Renderer, f: F.Frame) -> IO(Renderer & F.Frame):
  match f:
    case F.Failed{m}:
      IO.die(Renderer & F.Frame, 22, m)
    case F.Frame{+w, +h, +sc, +bg, ps, ds, +wh}:
      +regions = F.regions.of(ds, G.Box{0, 0, w, h}, Nil{})
      +whole = render.whole(r, wh, w, h, regions)
      render.at(render.still(whole, regions, r), whole, r, ps, regions, w, h, sc, bg)
