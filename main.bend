import Base
import ./color.bend as Color
import ./geometry.bend as G
import ./tree.bend as Tree

# A failed builder stays failed; finish exposes the error, never a fake image.
type Canvas is Type:
  Failed{message: String}
  Canvas{width: U32, height: U32, scale: F32, depth: Nat, side: U32,
    clip: G.Box, pixels: Image}

def reject(canvas: Canvas, reason: String) -> Canvas:
  match canvas:
    case Failed{message}:
      Failed{message}
    case Canvas{w, h, scale, d, s, clip, pixels}:
      Failed{reason}

def new.checked(valid: Bool, +width: U32, +height: U32, scale: F32, color: U32) -> Canvas:
  match valid:
    case False{}:
      Failed{"Chromi: dimensions 1..4096, scale (0,16], opaque background required"}
    case True{}:
      +depth = U32.log2((U32.max(width, height) - 1 : U32))
      # Side must be the next power of two, with a special case for 1x1.
      +d = Bool.pick(Nat, U32.is_eq(U32.max(width, height), 1), 0n, 1n+depth)
      Canvas{width, height, scale, d, (1 << d : U32), G.Box{0, 0, width, height}, Pix{color}}

def new(+width: U32, +height: U32, +scale: F32, +background: U32) -> Canvas:
  new.checked((width > 0 : U32) && (height > 0 : U32) &&
    (width <= 4096 : U32) && (height <= 4096 : U32) &&
    (scale > 0.0 : F32) && (scale <= 16.0 : F32) &&
    U32.is_eq(Color.alpha(background), 255), width, height, scale, background)

def physical(canvas: Canvas, box: G.Box, color: U32) -> Canvas:
  match canvas:
    case Failed{message}:
      Failed{message}
    case Canvas{w, h, scale, +depth, +side, +clip, pixels}:
      Canvas{w, h, scale, depth, side, clip,
        Tree.fill(depth, side, pixels, G.intersect(clip, box), color)}

def fill.valid(valid: Bool, canvas: Canvas, rect: G.Rect, color: U32) -> Canvas:
  match valid canvas:
    case _ Failed{message}:
      Failed{message}
    case False{} _:
      Failed{"Chromi: rectangle must be finite with nonnegative width and height"}
    case True{} Canvas{+w, +h, +scale, +depth, +side, +clip, pixels}:
      Canvas{w, h, scale, depth, side, clip,
        Tree.fill(depth, side, pixels, G.intersect(clip, G.physical(rect, scale, w, h)), color)}

def fill_rect(canvas: Canvas, +rect: G.Rect, color: U32) -> Canvas:
  fill.valid(G.valid(rect), canvas, rect, color)

def clip.valid(valid: Bool, canvas: Canvas, rect: G.Rect) -> Canvas:
  match valid canvas:
    case _ Failed{message}:
      Failed{message}
    case False{} _:
      Failed{"Chromi: invalid clip rectangle"}
    case True{} Canvas{+w, +h, +scale, d, s, clip, pixels}:
      Canvas{w, h, scale, d, s, G.intersect(clip, G.physical(rect, scale, w, h)), pixels}

def clip_rect(canvas: Canvas, +rect: G.Rect) -> Canvas:
  clip.valid(G.valid(rect), canvas, rect)

def reset_clip(canvas: Canvas) -> Canvas:
  match canvas:
    case Failed{message}:
      Failed{message}
    case Canvas{+w, +h, scale, d, s, clip, pixels}:
      Canvas{w, h, scale, d, s, G.Box{0, 0, w, h}, pixels}

def stroke.valid(valid: Bool, canvas: Canvas, rect: G.Rect, +thickness: F32, +color: U32) -> Canvas:
  match valid:
    case False{}:
      reject(canvas, "Chromi: invalid border geometry")
    case True{}:
      G.Rect{+x, +y, +w, +h} = rect
      +tx = F32.min(thickness, (w / 2.0 : F32))
      +ty = F32.min(thickness, (h / 2.0 : F32))
      a = fill_rect(canvas, G.Rect{x, y, w, ty}, color)
      b = fill_rect(a, G.Rect{x, (y + h - ty : F32), w, ty}, color)
      c = fill_rect(b, G.Rect{x, (y + ty : F32), tx, (h - 2.0 * ty : F32)}, color)
      fill_rect(c, G.Rect{(x + w - tx : F32), (y + ty : F32), tx, (h - 2.0 * ty : F32)}, color)

def stroke_rect(canvas: Canvas, +rect: G.Rect, +thickness: F32, color: U32) -> Canvas:
  stroke.valid(G.valid(rect) && G.finite(thickness) && (thickness >= 0.0 : F32),
    canvas, rect, thickness, color)

def circle.rows(fuel: Nat, canvas: Canvas, +width: U32, +y: U32,
  +cx: F32, +cy: F32, +radius: F32, +color: U32) -> Canvas:
  match fuel:
    case 0n:
      canvas
    case 1n+rest:
      +dy = (U32.to_f32(y) + 0.5 - cy : F32)
      +dx = F32.sqrt(F32.max(0.0, (radius * radius - dy * dy : F32)))
      box = {G.Box{G.edge((cx - dx : F32), width), y,
        G.edge((cx + dx : F32), width), (y + 1 : U32)} : G.Box}
      circle.rows(rest, physical(canvas, box, color), width, (y + 1 : U32), cx, cy, radius, color)

def circle.valid(valid: Bool, canvas: Canvas, +cx: F32, +cy: F32, +radius: F32, color: U32) -> Canvas:
  match valid canvas:
    case _ Failed{message}:
      Failed{message}
    case False{} _:
      Failed{"Chromi: invalid circle geometry"}
    case True{} Canvas{+w, +h, +scale, d, s, clip, pixels}:
      +top = G.edge(((cy - radius) * scale : F32), h)
      +bottom = G.edge(((cy + radius) * scale : F32), h)
      circle.rows(U32.to_nat((bottom - top : U32)),
        Canvas{w, h, scale, d, s, clip, pixels}, w, top,
        (cx * scale : F32), (cy * scale : F32), (radius * scale : F32), color)

def circle(canvas: Canvas, +cx: F32, +cy: F32, +radius: F32, color: U32) -> Canvas:
  circle.valid(G.finite(cx) && G.finite(cy) && G.finite(radius) && (radius >= 0.0 : F32),
    canvas, cx, cy, radius, color)

# The bitmap origin is logical; samples are physical pixels at 1:1 resolution.
# Text should rasterize at logical font size * device scale before calling this.
def blit.pixel(valid: Bool, canvas: Canvas, +x: F32, +y: F32, color: U32) -> Canvas:
  match valid:
    case False{}:
      canvas
    case True{}:
      +px = F32.to_u32(x)
      +py = F32.to_u32(y)
      physical(canvas, G.Box{px, py, (px + 1 : U32), (py + 1 : U32)}, color)

def blit.ink(mask: Bool, value: U32, ink: U32) -> U32:
  match mask:
    case False{}:
      value
    case True{}:
      Color.coverage(ink, value)

def blit.walk(data: List<&2, U32>, canvas: Canvas, +w: U32, +h: U32,
  +origin_x: F32, +origin_y: F32, +bw: U32, +index: U32, +mask: Bool, +ink: U32) -> Canvas:
  match data:
    case Nil{}:
      canvas
    case value <> rest:
      +x = (origin_x + U32.to_f32((index % bw : U32)) : F32)
      +y = (origin_y + U32.to_f32((index / bw : U32)) : F32)
      next = blit.pixel((x >= 0.0 : F32) && (y >= 0.0 : F32) &&
        (x < U32.to_f32(w) : F32) && (y < U32.to_f32(h) : F32),
        canvas, x, y, blit.ink(mask, value, ink))
      blit.walk(rest, next, w, h, origin_x, origin_y, bw, (index + 1 : U32), mask, ink)

def data_valid(data: List<&2, U32>, expected: Nat, +mask: Bool) -> Bool:
  match data expected:
    case Nil{} 0n:
      True{}
    case value <> rest 1n+n:
      (Bool.not(mask) || (value <= 255 : U32)) && data_valid(rest, n, mask)
    case _ _:
      False{}

def blit.valid(valid: Bool, canvas: Canvas, x: F32, y: F32, width: U32,
  data: List<&2, U32>, mask: Bool, ink: U32) -> Canvas:
  match valid canvas:
    case _ Failed{message}:
      Failed{message}
    case False{} _:
      Failed{"Chromi: invalid bitmap dimensions, data length, origin or coverage"}
    case True{} Canvas{+w, +h, +scale, d, s, clip, pixels}:
      blit.walk(data, Canvas{w, h, scale, d, s, clip, pixels}, w, h,
        F32.floor((x * scale : F32)), F32.floor((y * scale : F32)), width, 0, mask, ink)

def blit.bounds(valid: Bool, canvas: Canvas, x: F32, y: F32, +width: U32,
  height: U32, +data: List<&2, U32>, +mask: Bool, ink: U32) -> Canvas:
  match valid:
    case False{}:
      reject(canvas, "Chromi: bitmap dimensions or origin out of range")
    case True{}:
      blit.valid(data_valid(data, U32.to_nat((width * height : U32)), mask),
        canvas, x, y, width, data, mask, ink)

def blit_rgba(canvas: Canvas, +x: F32, +y: F32, +width: U32, +height: U32,
  data: List<&2, U32>) -> Canvas:
  blit.bounds((width <= 4096 : U32) && (height <= 4096 : U32) && G.finite(x) && G.finite(y),
    canvas, x, y, width, height, data, False{}, 0)

def blit_mask(canvas: Canvas, +x: F32, +y: F32, +width: U32, +height: U32,
  coverage: List<&2, U32>, ink: U32) -> Canvas:
  blit.bounds((width <= 4096 : U32) && (height <= 4096 : U32) && G.finite(x) && G.finite(y),
    canvas, x, y, width, height, coverage, True{}, ink)

def finish(canvas: Canvas) -> Result<&1, &1, U32 & String, Image>:
  match canvas:
    case Failed{message}:
      Fail{(22, message)}
    case Canvas{w, h, scale, d, s, clip, pixels}:
      Done{Tree.to_base_image(pixels)}

def pixel.valid(valid: Bool, pixels: Image, +side: U32, +x: U32, +y: U32) -> Maybe<U32>:
  match valid:
    case False{}:
      None{}
    case True{}:
      Some{Tree.sample(pixels, side, x, y, (x < side / 2 : U32), (y < side / 2 : U32))}

# Consumes the canvas: this is a diagnostic/test read, not a retained framebuffer.
def pixel(canvas: Canvas, +x: U32, +y: U32) -> Maybe<U32>:
  match canvas:
    case Failed{message}:
      None{}
    case Canvas{w, h, scale, d, side, clip, pixels}:
      pixel.valid((x < w : U32) && (y < h : U32), pixels, side, x, y)
