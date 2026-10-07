import Base

type Rect is Data:
  Rect{x: F32, y: F32, width: F32, height: F32}

type Box is Data:
  Box{x0: U32, y0: U32, x1: U32, y1: U32}

def finite(+x: F32) -> Bool:
  (x >= F32.neg(1048576.0) : F32) && (x <= 1048576.0 : F32)

def valid(rect: Rect) -> Bool:
  Rect{x, y, +w, +h} = rect
  finite(x) && finite(y) && finite(w) && finite(h) &&
    (w >= 0.0 : F32) && (h >= 0.0 : F32)

def edge(x: F32, extent: U32) -> U32:
  F32.to_u32(F32.clamp(F32.ceil((x - 0.5 : F32)), 0.0, U32.to_f32(extent)))

# Pixel-centre coverage, final edge exclusive; clamp before unsigned conversion.
def physical(rect: Rect, +scale: F32, +width: U32, +height: U32) -> Box:
  Rect{+x, +y, w, h} = rect
  Box{edge((x * scale : F32), width), edge((y * scale : F32), height),
    edge(((x + w) * scale : F32), width), edge(((y + h) * scale : F32), height)}

def intersect(a: Box, b: Box) -> Box:
  Box{ax, ay, ar, ab} = a
  Box{bx, by, br, bb} = b
  Box{U32.max(ax, bx), U32.max(ay, by), U32.min(ar, br), U32.min(ab, bb)}

def empty(box: Box) -> Bool:
  Box{x, y, r, b} = box
  (x >= r : U32) || (y >= b : U32)

def overlaps(box: Box, +x: U32, +y: U32, +side: U32) -> Bool:
  Box{left, top, right, bottom} = box
  (left < x + side : U32) && (top < y + side : U32) &&
    (right > x : U32) && (bottom > y : U32)

def contains(box: Box, +x: U32, +y: U32, +side: U32) -> Bool:
  Box{left, top, right, bottom} = box
  (left <= x : U32) && (top <= y : U32) &&
    (right >= x + side : U32) && (bottom >= y + side : U32)

# Boxes of pixels
# ---------------
# Draw-list coordinates are signed 32-bit values in U32 bits; boxes are
# surface pixels (unsigned, end exclusive).

def slt(+a: U32, +b: U32) -> Bool:
  U32.is_lt((a .^. 2147483648 : U32), (b .^. 2147483648 : U32))

def smax(+a: U32, +b: U32) -> U32:
  Bool.pick(U32, slt(a, b), b, a)

def smin(+a: U32, +b: U32) -> U32:
  Bool.pick(U32, slt(a, b), a, b)

# Signed floor and ceiling of v / 8 (1/8 pixels to pixels).
def floor8(+v: U32) -> U32:
  Bool.pick(U32, slt(v, 0), (0 - (((0 - v : U32) + 7 : U32) / 8 : U32) : U32), (v / 8 : U32))

def ceil8(+v: U32) -> U32:
  (0 - floor8((0 - v : U32)) : U32)

# Whether the pixels [x, x + w) x [y, y + h), x and y signed, meet the box.
def meets(box: Box, +x: U32, +y: U32, +w: U32, +h: U32) -> Bool:
  Box{+left, +top, +right, +bottom} = box
  U32.is_lt(left, right) && U32.is_lt(top, bottom) && U32.is_ne(w, 0) && U32.is_ne(h, 0) &&
    slt(left, (x + w : U32)) && slt(x, right) && slt(top, (y + h : U32)) && slt(y, bottom)

# The part of the box those pixels cover (empty when they miss it).
def cover.pick(hit: Bool, box: Box, +x: U32, +y: U32, +w: U32, +h: U32) -> Box:
  match hit:
    case False{}:
      Box{0, 0, 0, 0}
    case True{}:
      Box{+left, +top, +right, +bottom} = box
      Box{smax(left, x), smax(top, y), smin(right, (x + w : U32)), smin(bottom, (y + h : U32))}

def cover(+box: Box, +x: U32, +y: U32, +w: U32, +h: U32) -> Box:
  cover.pick(meets(box, x, y, w, h), box, x, y, w, h)

def union.pick(a_empty: Bool, b_empty: Bool, a: Box, b: Box) -> Box:
  match a_empty b_empty:
    case True{} _:
      b
    case False{} True{}:
      a
    case False{} False{}:
      Box{ax, ay, ar, ab} = a
      Box{bx, by, br, bb} = b
      Box{U32.min(ax, bx), U32.min(ay, by), U32.max(ar, br), U32.max(ab, bb)}

# The smallest box holding both; an empty box adds nothing.
def union(+a: Box, +b: Box) -> Box:
  union.pick(empty(a), empty(b), a, b)

def area.pick(none: Bool, box: Box) -> U32:
  match none:
    case True{}:
      0
    case False{}:
      Box{x, y, r, b} = box
      ((r - x) * (b - y) : U32)

def area(+box: Box) -> U32:
  area.pick(empty(box), box)

def meet(+a: Box, +b: Box) -> Bool:
  Bool.not(empty(intersect(a, b)))
