import Base
import ../../scene.bend as S
import ../../../Ocula/main.bend as O
import ../../../Ocula/file.bend as OF
import ../../../Ocula/pixels.bend as Pixels
import ../../../Splina/main.bend as Sp
import ../../../Splina/file.bend as SF
import ../../../Splina/path.bend as P
import ../../../Splina/geometry.bend as SG
import ../../../Splina/style.bend as Style
import ../../../Dithra/raster.bend as R

# Media for the integrated demo, prepared once at startup: a PNG decoded by
# Ocula (straight RGBA8 words) and an SVG parsed by Splina whose shapes
# Dithra rasterizes into coverage masks at a fixed pixel size. Both become
# Chromi operations with fixed keys, so the GPU atlas uploads them once.

def png_key() -> U32:
  268435457

def svg_key(+i: U32) -> U32:
  (536870912 + i : U32)

# The decoded PNG as validated Chromi pixels.
type Picture is Data:
  Picture{width: U32, height: U32, pixels: S.Pixels}

# One SVG shape: its offset in the fitted square, its coverage as validated
# Chromi pixels, and its fill color.
type Shape is Data:
  Shape{left: F32, top: F32, pixels: S.Pixels, color: U32}

def pass(-A: Data, r: Result<&2, &1, String, A>) -> IO(A):
  SF.pass(A, r)

def picture.made(+w: U32, +h: U32, r: Result<&2, &2, String, S.Pixels>) -> IO(Picture):
  match r:
    case Fail{message}:
      IO.die(Picture, 1, message)
    case Done{p}:
      IO.pure(Picture, Picture{w, h, p})

def picture(r: Pixels.Raster) -> IO(Picture):
  match r:
    case Pixels.Raster{+w, +h, px}:
      picture.made(w, h, S.rgba(png_key(), w, h, Pixels.packed_pixels(Pixels.Raster{w, h, px})))

# The PNG at `path`, decoded in Bend.
def png(path: String) -> IO(Picture):
  do IO<Picture>:
    bytes : +List<U32> <- OF.read(path)
    raster : Pixels.Raster <- SF.pass(Pixels.Raster, O.decode_png(bytes))
    picture(raster)

def mask(r: Result<&2, &2, String, R.Mask>) -> Result<&2, &1, String, R.Mask>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{m}:
      Done{m}

def shape.made(+left: F32, +top: F32, r: Result<&2, &2, String, S.Pixels>, +color: U32) ->
  Result<&2, &1, String, Shape>:
  match r:
    case Fail{message}:
      Fail{message}
    case Done{p}:
      Done{Shape{left, top, p, color}}

def shape(m: R.Mask, +i: U32, +color: U32) -> Result<&2, &1, String, Shape>:
  match m:
    case R.Mask{+w, +h, +left, +top, adv, cov}:
      shape.made(left, top, S.coverage(svg_key(i), w, h, cov), color)

def shapes(xs: +List<Sp.Shape>, +t: P.Transform, +i: U32) -> Result<&2, &1, String, List<&2, Shape>>:
  match xs:
    case Nil{}:
      Done{Nil{}}
    case Sp.Shape{path, +fill} <> rest:
      do Result<&2, &1, String, List<&2, Shape>>:
        filled : P.Path <- SG.for_fill(P.transform(path, t))
        coverage : R.Mask <- mask(R.rasterize_screen(filled, 0.0))
        one : Shape <- shape(coverage, i, fill)
        more : List<&2, Shape> <- shapes(rest, t, (i + 1 : U32))
        return one <> more

# The SVG fitted into a size x size pixel square at the origin (xMidYMid
# meet, as Splina's render.bend), one coverage mask per shape.
def fitted(svg: Sp.Svg, +size: F32) -> Result<&2, &1, String, List<&2, Shape>>:
  match svg:
    case Sp.Svg{_, _, Style.Box{vx, vy, +vw, +vh}, xs}:
      +scale = F32.min((size / vw : F32), (size / vh : F32))
      shapes(xs, P.compose(P.translate(((size - vw * scale) * 0.5 : F32), ((size - vh * scale) * 0.5 : F32)),
        P.compose(P.scale(scale, scale), P.translate(F32.neg(vx), F32.neg(vy)))), 0)

# The SVG at `path`, `currentColor` resolved to `color`, rasterized at size.
def svg(path: String, +color: U32, +size: F32) -> IO(List<&2, Shape>):
  do IO<List<&2, Shape>>:
    source : String <- SF.read(path)
    doc : Sp.Svg <- pass(Sp.Svg, Sp.parse_svg_with_color(source, color))
    pass(List<&2, Shape>, fitted(doc, size))

# Painting
# --------

def paint_picture(s: S.Scene, p: Picture, +x: F32, +y: F32) -> S.Scene:
  Picture{w, h, px} = p
  S.draw(s, px, x, y, 0)

def paint_shapes(xs: List<&2, Shape>, s: S.Scene, +x: F32, +y: F32) -> S.Scene:
  match xs:
    case Nil{}:
      s
    case Con{Shape{+left, +top, p, color}, rest}:
      paint_shapes(rest, S.draw(s, p, (x + left : F32), (y + top : F32), color), x, y)

def paint_svg(s: S.Scene, xs: List<&2, Shape>, +x: F32, +y: F32) -> S.Scene:
  paint_shapes(xs, s, x, y)
