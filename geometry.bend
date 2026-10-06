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
