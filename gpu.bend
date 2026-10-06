import Base
import ./geometry.bend as G
import ./scene.bend as S
import ../Voltra/gpu.bend as V
import ../Voltra/quads.bend as Q
import ../Voltra/atlas.bend as At

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

type Renderer is Data:
  Renderer{gpu: V.Gpu, atlas: At.Atlas, uploaded: U32, resets: U32}

def ready(+g: V.Gpu) -> IO(Renderer):
  do IO<Renderer>:
    +g1 : V.Gpu <- V.blank(g, atlas_size(), atlas_size())
    return Renderer{g1, At.new(atlas_size(), atlas_size()), 0, 0}

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
  Renderer{g, a, u, n} = r
  g

def with_gpu(r: Renderer, +g: V.Gpu) -> Renderer:
  Renderer{old, a, u, n} = r
  Renderer{g, a, u, n}

# Texels uploaded to the atlas so far, and how often it started over.
def uploaded(r: Renderer) -> U32:
  Renderer{g, a, u, n} = r
  u

def resets(r: Renderer) -> U32:
  Renderer{g, a, u, n} = r
  n

def entries(r: Renderer) -> U32:
  Renderer{g, a, u, n} = r
  At.count(a)

def pending(r: Renderer) -> Bool:
  V.pending(gpu(r))

def invalidate(r: Renderer) -> Renderer:
  Renderer{g, a, u, n} = r
  Renderer{V.invalidate(g), a, u, n}

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
  Renderer{g, old, +u, +n} = r
  Plan{a, rs, qs, +t, f} = p
  do IO<Renderer>:
    +g1 : V.Gpu <- V.update(g, rs)
    +g2 : V.Gpu <- V.draw(g1, qs, clear)
    return Renderer{g2, a, (u + t : U32), (n + Bool.to_u32(reset) : U32)}

def draw.planned(overflow: Bool, +r: Renderer, +os: List<&2, S.Op>, p: Plan, +clear: U32) -> IO(Renderer):
  match overflow:
    case False{}:
      submit(r, p, clear, False{})
    case True{}:
      # Start the atlas over with only what this frame needs.
      Renderer{g, a, u, n} = r
      submit(r, plan(os, At.reset(a)), clear, True{})

def draw.ops(res: Result<&1, &1, U32 & String, List<&2, S.Op>>, +r: Renderer, +clear: U32) -> IO(Renderer):
  match res:
    case Fail{(code, message)}:
      IO.die(Renderer, code, message)
    case Done{+os}:
      Renderer{g, +a, u, n} = r
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
