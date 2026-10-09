import Base
import ./geometry.bend as G
import ./scene.bend as S

# Retained frames
# ===============
#
# A frame as parts, in drawing order (later parts on top). Each part has a
# stable id chosen by the app (the Kairo or Mokko id of a control, the
# layout id of a block of content), the draw list it recorded (scene.bend)
# and the box of surface pixels that list can touch. The next frame is
# built from the last one: a part whose content did not change is kept as
# it was, with what a renderer derived from it (the GPU path's stored
# quads), and is neither recorded nor planned again. The frame records as
# damage the boxes where its picture may differ from the last one: the old
# and the new box of each changed part and the boxes of parts added or
# removed. A renderer then redraws only the damage over the last picture,
# which equals drawing the whole frame (replay.bend's `repaint` does it on
# the CPU, gpu.bend's `render` on the GPU; the tests compare both with a
# whole redraw). A new surface, the first frame or a lost picture are drawn
# whole.
#
# How a part knows it did not change is the app's choice:
#   part     records the part every frame and compares its operations with
#            the kept ones (cheap for a few dozen operations);
#   stamped  records the part only when its stamp differs from the kept
#            one: the app promises that an equal stamp draws the same
#            (large content that rarely changes, such as a grid of labels).
# Each part is a separate draw list that starts with the whole surface as
# its clip. Ids are matched in order: a part is normally found at once;
# parts moved, added or removed cost a scan of the rest.

# What a renderer derived from a part's operations, valid while the part is
# kept (Chromi's GPU path: its quads written once into Voltra's store, at
# [first, first + quads), and the epoch of the atlas and the store they
# belong to).
type Cache is Data:
  Unplanned{}
  Planned{epoch: U32, quads: U32, first: U32}

type Part is Data:
  Part{id: U32, stamp: U32, bounds: G.Box, ops: List<&2, S.Op>, cache: Cache}

type Frame is Data:
  Failed{message: String}
  Frame{width: U32, height: U32, scale: F32, background: U32, parts: List<&2, Part>,
    damage: List<&2, G.Box>, whole: Bool}

# The frame before the first: the next one is drawn whole.
def none() -> Frame:
  Frame{0, 0, 1.0, 255, Nil{}, Nil{}, True{}}

def part.id(p: Part) -> U32:
  Part{id, st, b, os, c} = p
  id

def part.stamp(p: Part) -> U32:
  Part{id, st, b, os, c} = p
  st

def part.bounds(p: Part) -> G.Box:
  Part{id, st, b, os, c} = p
  b

def part.ops(p: Part) -> List<&2, S.Op>:
  Part{id, st, b, os, c} = p
  os

def part.cache(p: Part) -> Cache:
  Part{id, st, b, os, c} = p
  c

def part.cached(p: Part, c: Cache) -> Part:
  Part{id, st, b, os, old} = p
  Part{id, st, b, os, c}

def made(+id: U32, +stamp: U32, +ops: List<&2, S.Op>) -> Part:
  Part{id, stamp, S.bounds(ops, G.Box{0, 0, 0, 0}), ops, Unplanned{}}

def nothing() -> G.Box:
  G.Box{0, 0, 0, 0}

# Building
# --------

type Build is Data:
  Broken{message: String}
  Build{width: U32, height: U32, scale: F32, background: U32, old: List<&2, Part>,
    parts: List<&2, Part>, damage: List<&2, G.Box>, whole: Bool}

def begin.same(same: Bool, old: List<&2, Part>, damage: List<&2, G.Box>, +whole: Bool,
  +w: U32, +h: U32, +sc: F32, +bg: U32) -> Build:
  match same:
    case True{}:
      Build{w, h, sc, bg, old, Nil{}, damage, whole}
    case False{}:
      Build{w, h, sc, bg, Nil{}, Nil{}, Nil{}, True{}}

# Starts the frame of a w x h surface (scale, opaque background) after
# `last`. Parts are kept only on the same surface; otherwise every part is
# recorded again and the frame is drawn whole. Damage that `last` still
# carried (a frame never drawn) carries over.
def begin(last: Frame, +w: U32, +h: U32, +sc: F32, +bg: U32) -> Build:
  match last:
    case Failed{m}:
      Build{w, h, sc, bg, Nil{}, Nil{}, Nil{}, True{}}
    case Frame{+lw, +lh, +lsc, +lbg, parts, damage, whole}:
      begin.same(U32.is_eq(lw, w) && U32.is_eq(lh, h) && F32.is_eq(lsc, sc) && U32.is_eq(lbg, bg),
        parts, damage, whole, w, h, sc, bg)

# An empty scene of the frame's surface, for a part to record into.
def blank(b: Build) -> S.Scene:
  match b:
    case Broken{m}:
      S.Failed{m}
    case Build{w, h, sc, bg, old, parts, damage, whole}:
      S.new(w, h, sc, bg)

type Taken is Data:
  Taken{found: Maybe<&2, Part>, removed: List<&2, G.Box>, rest: List<&2, Part>}

def take.step(hit: Bool, +p: Part, +rest: List<&2, Part>, skipped: List<&2, G.Box>,
  later: List<&2, G.Box> -> Maybe<&2, Taken>) -> Maybe<&2, Taken>:
  match hit:
    case True{}:
      Some{Taken{Some{p}, skipped, rest}}
    case False{}:
      later(part.bounds(p) <> skipped)

def take.find(xs: List<&2, Part>, +id: U32, skipped: List<&2, G.Box>) -> Maybe<&2, Taken>:
  match xs:
    case Nil{}:
      None{}
    case Con{+p, +rest}:
      take.step(U32.is_eq(part.id(p), id), p, rest, skipped, more => take.find(rest, id, more))

def take.later(m: Maybe<&2, Taken>, +old: List<&2, Part>) -> Taken:
  match m:
    case None{}:
      Taken{None{}, Nil{}, old}
    case Some{t}:
      t

def take.head(hit: Bool, +p: Part, +rest: List<&2, Part>, +id: U32) -> Taken:
  match hit:
    case True{}:
      Taken{Some{p}, Nil{}, rest}
    case False{}:
      take.later(take.find(rest, id, [part.bounds(p)]), p <> rest)

# The last frame's part with this id: normally the first one not yet met.
# Parts skipped to reach it were removed (their boxes are damaged); when no
# part has the id, nothing is consumed.
def take(old: List<&2, Part>, +id: U32) -> Taken:
  match old:
    case Nil{}:
      Taken{None{}, Nil{}, Nil{}}
    case Con{+p, +rest}:
      take.head(U32.is_eq(part.id(p), id), p, rest, id)

def damage.add(none: Bool, b: G.Box, acc: List<&2, G.Box>) -> List<&2, G.Box>:
  match none:
    case True{}:
      acc
    case False{}:
      b <> acc

def damage.push(+b: G.Box, acc: List<&2, G.Box>) -> List<&2, G.Box>:
  damage.add(G.empty(b), b, acc)

# The next part of the frame is `p`; `gone` and `fresh` are the boxes it
# changed (empty when it was kept), `removed` those of parts removed
# before it, and `rest` the last frame's parts still to meet.
def settle(b: Build, rest: List<&2, Part>, removed: List<&2, G.Box>, +p: Part, +gone: G.Box,
  +fresh: G.Box) -> Build:
  match b:
    case Broken{m}:
      Broken{m}
    case Build{w, h, sc, bg, old, parts, damage, whole}:
      Build{w, h, sc, bg, rest, p <> parts,
        damage.push(gone, damage.push(fresh, List.append(&2, G.Box, removed, damage))), whole}

def part.same(same: Bool, +old: Part, +new: Part, b: Build, rest: List<&2, Part>,
  removed: List<&2, G.Box>) -> Build:
  match same:
    case True{}:
      settle(b, rest, removed, old, nothing(), nothing())
    case False{}:
      settle(b, rest, removed, new, part.bounds(old), part.bounds(new))

def part.compared(found: Maybe<&2, Part>, +new: Part, b: Build, rest: List<&2, Part>,
  removed: List<&2, G.Box>) -> Build:
  match found:
    case None{}:
      settle(b, rest, removed, new, nothing(), part.bounds(new))
    case Some{+old}:
      part.same(S.same_ops(part.ops(old), part.ops(new)), old, new, b, rest, removed)

def part.recorded(r: Result<&1, &1, U32 & String, List<&2, S.Op>>, t: Taken, +id: U32,
  b: Build) -> Build:
  match r:
    case Fail{(code, message)}:
      Broken{message}
    case Done{ops}:
      Taken{found, removed, rest} = t
      part.compared(found, made(id, 0, ops), b, rest, removed)

# A part recorded every frame: `draw` records it into an empty scene of the
# frame's surface. When the last frame's part with this id recorded the
# same operations, that part is kept (with what a renderer derived from
# it) and nothing is damaged; otherwise the new part replaces it and both
# of their boxes are damaged. A failed scene fails the frame.
def part(b: Build, +id: U32, draw: S.Scene -> S.Scene) -> Build:
  match b:
    case Broken{m}:
      Broken{m}
    case Build{+w, +h, +sc, +bg, old, parts, damage, whole}:
      part.recorded(S.ops(draw(S.new(w, h, sc, bg))), take(old, id), id,
        Build{w, h, sc, bg, Nil{}, parts, damage, whole})

def bounds.of(m: Maybe<&2, Part>) -> G.Box:
  match m:
    case None{}:
      nothing()
    case Some{p}:
      part.bounds(p)

def stamped.recorded(r: Result<&1, &1, U32 & String, List<&2, S.Op>>, old: Maybe<&2, Part>,
  +id: U32, +stamp: U32, b: Build, rest: List<&2, Part>, removed: List<&2, G.Box>) -> Build:
  match r:
    case Fail{(code, message)}:
      Broken{message}
    case Done{ops}:
      +new = made(id, stamp, ops)
      settle(b, rest, removed, new, bounds.of(old), part.bounds(new))

def stamped.same(same: Bool, +old: Part, +id: U32, +stamp: U32, draw: S.Scene -> S.Scene,
  +b: Build, rest: List<&2, Part>, removed: List<&2, G.Box>) -> Build:
  match same:
    case True{}:
      settle(b, rest, removed, old, nothing(), nothing())
    case False{}:
      stamped.recorded(S.ops(draw(blank(b))), Some{old}, id, stamp, b, rest, removed)

def stamped.found(m: Maybe<&2, Part>, +id: U32, +stamp: U32, draw: S.Scene -> S.Scene,
  +b: Build, rest: List<&2, Part>, removed: List<&2, G.Box>) -> Build:
  match m:
    case None{}:
      stamped.recorded(S.ops(draw(blank(b))), None{}, id, stamp, b, rest, removed)
    case Some{+old}:
      stamped.same(U32.is_eq(part.stamp(old), stamp), old, id, stamp, draw, b, rest, removed)

def stamped.taken(t: Taken, +id: U32, +stamp: U32, draw: S.Scene -> S.Scene, b: Build) -> Build:
  Taken{found, removed, rest} = t
  stamped.found(found, id, stamp, draw, b, rest, removed)

# A part recorded only when its stamp differs from the kept part's (or
# none has this id): the app promises that an equal stamp draws the same.
def stamped(b: Build, +id: U32, +stamp: U32, draw: S.Scene -> S.Scene) -> Build:
  match b:
    case Broken{m}:
      Broken{m}
    case Build{+w, +h, +sc, +bg, old, parts, damage, whole}:
      stamped.taken(take(old, id), id, stamp, draw, Build{w, h, sc, bg, Nil{}, parts, damage, whole})

def boxes(ps: List<&2, Part>, acc: List<&2, G.Box>) -> List<&2, G.Box>:
  match ps:
    case Nil{}:
      acc
    case Con{p, rest}:
      boxes(rest, damage.push(part.bounds(p), acc))

# The frame. Parts of the last frame not met again were removed: their
# boxes are damaged.
def end(b: Build) -> Frame:
  match b:
    case Broken{m}:
      Failed{m}
    case Build{w, h, sc, bg, old, parts, damage, whole}:
      Frame{w, h, sc, bg, List.reverse(&2, Part, parts), boxes(old, damage), whole}

# Reading frames
# --------------

def size(f: Frame) -> U32 & U32:
  match f:
    case Failed{m}:
      (0, 0)
    case Frame{w, h, sc, bg, ps, ds, wh}:
      (w, h)

def background(f: Frame) -> U32:
  match f:
    case Failed{m}:
      0
    case Frame{w, h, sc, bg, ps, ds, wh}:
      bg

def parts(f: Frame) -> List<&2, Part>:
  match f:
    case Failed{m}:
      Nil{}
    case Frame{w, h, sc, bg, ps, ds, wh}:
      ps

def damage(f: Frame) -> List<&2, G.Box>:
  match f:
    case Failed{m}:
      Nil{}
    case Frame{w, h, sc, bg, ps, ds, wh}:
      ds

# Whether the frame must be drawn whole (a first frame, a new surface).
def whole(f: Frame) -> Bool:
  match f:
    case Failed{m}:
      True{}
    case Frame{w, h, sc, bg, ps, ds, wh}:
      wh

def count(f: Frame) -> U32:
  U32.from_nat(List.length(&2, Part, parts(f)))

# The frame once a renderer drew it: its parts (with what the renderer
# derived from them) and no damage left.
def drawn(f: Frame, ps: List<&2, Part>) -> Frame:
  match f:
    case Failed{m}:
      Failed{m}
    case Frame{w, h, sc, bg, old, ds, wh}:
      Frame{w, h, sc, bg, ps, Nil{}, False{}}

def all_ops(ps: List<&2, Part>) -> List<&2, S.Op>:
  match ps:
    case Nil{}:
      Nil{}
    case Con{Part{id, st, b, os, c}, rest}:
      List.append(&2, S.Op, os, all_ops(rest))

# The frame as one draw list: every part's operations in order (as a scene
# that recorded the same calls would hold them).
def ops(f: Frame) -> Result<&1, &1, U32 & String, List<&2, S.Op>>:
  match f:
    case Failed{m}:
      Fail{(22, m)}
    case Frame{w, h, sc, bg, ps, ds, wh}:
      Done{all_ops(ps)}

# Damage regions
# --------------

def merge.keep(hit: Bool, a: G.Box, apart: List<&2, G.Box>) -> List<&2, G.Box>:
  match hit:
    case True{}:
      apart
    case False{}:
      a <> apart

# Adds a box to disjoint boxes, joining it with every box it meets.
def merge.into(acc: List<&2, G.Box>, +b: G.Box, apart: List<&2, G.Box>) -> List<&2, G.Box>:
  match acc:
    case Nil{}:
      b <> apart
    case Con{+a, rest}:
      +hit = G.meet(a, b)
      merge.into(rest, Bool.pick(G.Box, hit, G.union(a, b), b), merge.keep(hit, a, apart))

def merge.cut(none: Bool, +c: G.Box, acc: List<&2, G.Box>) -> List<&2, G.Box>:
  match none:
    case True{}:
      acc
    case False{}:
      merge.into(acc, c, Nil{})

def regions.of(ds: List<&2, G.Box>, +surface: G.Box, acc: List<&2, G.Box>) -> List<&2, G.Box>:
  match ds:
    case Nil{}:
      acc
    case Con{d, rest}:
      +c = G.intersect(surface, d)
      regions.of(rest, surface, merge.cut(G.empty(c), c, acc))

# The damaged boxes to redraw, within the surface, joined where they meet;
# empty when nothing changed. Boxes may still overlap (a join can reach a
# box met earlier): redrawing a pixel twice gives the same picture.
def regions(f: Frame) -> List<&2, G.Box>:
  match f:
    case Failed{m}:
      Nil{}
    case Frame{+w, +h, sc, bg, ps, ds, wh}:
      regions.of(ds, G.Box{0, 0, w, h}, Nil{})

def area(bs: List<&2, G.Box>, +acc: U32) -> U32:
  match bs:
    case Nil{}:
      acc
    case Con{b, rest}:
      area(rest, (acc + G.area(b) : U32))

# Whether the part meets any of the boxes.
def touched(bs: List<&2, G.Box>, +box: G.Box) -> Bool:
  match bs:
    case Nil{}:
      False{}
    case Con{b, rest}:
      G.meet(b, box) || touched(rest, box)
