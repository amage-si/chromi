import Base
import ./color.bend as C
import ./geometry.bend as G

# The renderer stores straight RGBA8. Base.Image presents opaque RGB in its
# low 24 bits; composition has already resolved alpha before this boundary.
def to_base_image(image: Image) -> Image:
  match image:
    case Pix{rgba}:
      Pix{(rgba >> 8n : U32)}
    case Qua{tl, tr, bl, br}:
      Qua{to_base_image(tl), to_base_image(tr), to_base_image(bl), to_base_image(br)}

def compact.same(same: Bool, a: U32, b: U32, c: U32, d: U32) -> Image:
  match same:
    case True{}:
      Pix{a}
    case False{}:
      Qua{Pix{a}, Pix{b}, Pix{c}, Pix{d}}

def compact(a: Image, b: Image, c: Image, d: Image) -> Image:
  match a b c d:
    case Pix{+w} Pix{+x} Pix{+y} Pix{+z}:
      compact.same(U32.is_eq(w, x) && U32.is_eq(x, y) && U32.is_eq(y, z), w, x, y, z)
    case a b c d:
      Qua{a, b, c, d}

def blend(image: Image, +color: U32) -> Image:
  match image:
    case Pix{old}:
      Pix{C.over(color, old)}
    case Qua{a, b, c, d}:
      compact(blend(a, color), blend(b, color), blend(c, color), blend(d, color))

def cover(opaque: Bool, image: Image, color: U32) -> Image:
  match opaque:
    case True{}:
      Pix{color}
    case False{}:
      blend(image, color)

# Finite depth guarantees termination. Uniform regions stay as a single Pix.
def paint(+depth: Nat, image: Image, +box: G.Box, +color: U32,
  +x: U32, +y: U32, +side: U32, overlap: Bool, inside: Bool) -> Image:
  match depth image overlap inside:
    case _ image False{} _:
      image
    case _ image _ True{}:
      cover(U32.is_eq(C.alpha(color), 255), image, color)
    case 0n image True{} False{}:
      blend(image, color)
    case 1n+remaining Pix{+old} True{} False{}:
      +half = (side / 2 : U32)
      +right = (x + half : U32)
      +bottom = (y + half : U32)
      compact(
        paint(remaining, Pix{old}, box, color, x, y, half,
          G.overlaps(box, x, y, half), G.contains(box, x, y, half)),
        paint(remaining, Pix{old}, box, color, right, y, half,
          G.overlaps(box, right, y, half), G.contains(box, right, y, half)),
        paint(remaining, Pix{old}, box, color, x, bottom, half,
          G.overlaps(box, x, bottom, half), G.contains(box, x, bottom, half)),
        paint(remaining, Pix{old}, box, color, right, bottom, half,
          G.overlaps(box, right, bottom, half), G.contains(box, right, bottom, half)))
    case 1n+remaining Qua{a, b, c, d} True{} False{}:
      +half = (side / 2 : U32)
      +right = (x + half : U32)
      +bottom = (y + half : U32)
      compact(
        paint(remaining, a, box, color, x, y, half,
          G.overlaps(box, x, y, half), G.contains(box, x, y, half)),
        paint(remaining, b, box, color, right, y, half,
          G.overlaps(box, right, y, half), G.contains(box, right, y, half)),
        paint(remaining, c, box, color, x, bottom, half,
          G.overlaps(box, x, bottom, half), G.contains(box, x, bottom, half)),
        paint(remaining, d, box, color, right, bottom, half,
          G.overlaps(box, right, bottom, half), G.contains(box, right, bottom, half)))

def fill.empty(skip: Bool, depth: Nat, side: U32, image: Image,
  box: G.Box, color: U32) -> Image:
  match skip:
    case True{}:
      image
    case False{}:
      paint(depth, image, box, color, 0, 0, side, True{}, False{})

def fill(depth: Nat, side: U32, image: Image, +box: G.Box, +color: U32) -> Image:
  fill.empty(G.empty(box) || U32.is_eq(C.alpha(color), 0), depth, side, image, box, color)

def sample(image: Image, +side: U32, +x: U32, +y: U32, left: Bool, top: Bool) -> U32:
  match image left top:
    case Pix{color} _ _:
      color
    case Qua{a, b, c, d} True{} True{}:
      +half = (side / 2 : U32)
      sample(a, half, x, y, (x < half / 2 : U32), (y < half / 2 : U32))
    case Qua{a, b, c, d} False{} True{}:
      +half = (side / 2 : U32)
      +nx = (x - half : U32)
      sample(b, half, nx, y, (nx < half / 2 : U32), (y < half / 2 : U32))
    case Qua{a, b, c, d} True{} False{}:
      +half = (side / 2 : U32)
      +ny = (y - half : U32)
      sample(c, half, x, ny, (x < half / 2 : U32), (ny < half / 2 : U32))
    case Qua{a, b, c, d} False{} False{}:
      +half = (side / 2 : U32)
      +nx = (x - half : U32)
      +ny = (y - half : U32)
      sample(d, half, nx, ny, (nx < half / 2 : U32), (ny < half / 2 : U32))
