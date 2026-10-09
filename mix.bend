import Base
import ./color.bend as Color

# Colour interpolation for animations and gradients: in OKLab, in linear light
# and in encoded sRGB. Colours are 0xRRGGBBAA, sRGB-encoded, straight alpha.
# This is not how Chromi composites (that stays in encoded sRGB, color.bend).

# A colour in OKLab (Björn Ottosson, 2020): L lightness in 0..1, a green-red,
# b blue-yellow.
type Lab is Data:
  Lab{l: F32, a: F32, b: F32}

# OKLCH: the same lightness, chroma c = |(a, b)|, hue h in radians (-pi..pi).
type Lch is Data:
  Lch{l: F32, c: F32, h: F32}

# Linear-light sRGB (red, green, blue), 0..1 within the gamut.
type Rgb is Data:
  Rgb{r: F32, g: F32, b: F32}

# The sRGB transfer function (IEC 61966-2-1)
# -------------------------------------------

# Encoded (0..1) to linear light.
def to_linear.go(low: Bool, +v: F32) -> F32:
  match low:
    case True{}:
      (v / 12.92 : F32)
    case False{}:
      F32.pow(((v + 0.055) / 1.055 : F32), 2.4)

def to_linear(+v: F32) -> F32:
  to_linear.go((v <= 0.04045 : F32), v)

# Linear light to encoded, clamped to 0..1 (NaN gives 0).
def to_srgb.go(high: Bool, +v: F32) -> F32:
  match high:
    case False{}:
      F32.max((v * 12.92 : F32), 0.0)
    case True{}:
      F32.min((1.055 * F32.pow(v, 0.41666666) - 0.055 : F32), 1.0)

def to_srgb(+v: F32) -> F32:
  to_srgb.go((v > 0.0031308 : F32), v)

# A byte channel (0..255) to linear light.
def byte_to_linear(+c: U32) -> F32:
  to_linear((U32.to_f32(c) / 255.0 : F32))

# Linear light to a byte channel: clamped, rounded to nearest.
def linear_to_byte(+v: F32) -> U32:
  F32.to_u32(F32.floor((to_srgb(v) * 255.0 + 0.5 : F32)))

def rgb(+c: U32) -> Rgb:
  Rgb{byte_to_linear(Color.red(c)), byte_to_linear(Color.green(c)), byte_to_linear(Color.blue(c))}

# Linear light to 0xRRGGBBAA with this alpha byte.
def rgba(v: Rgb, +alpha: U32) -> U32:
  match v:
    case Rgb{+r, +g, +b}:
      Color.pack(linear_to_byte(r), linear_to_byte(g), linear_to_byte(b), alpha)

# OKLab
# -----

# Cube root of a nonnegative value (LMS of colours in the gamut is >= 0).
def cbrt.go(positive: Bool, +x: F32) -> F32:
  match positive:
    case False{}:
      0.0
    case True{}:
      F32.pow(x, 0.33333334)

def cbrt(+x: F32) -> F32:
  cbrt.go((x > 0.0 : F32), x)

def lab.of(+l: F32, +m: F32, +s: F32) -> Lab:
  Lab{(0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s : F32),
    (1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s : F32),
    (0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s : F32)}

# Linear sRGB to OKLab.
def oklab(v: Rgb) -> Lab:
  match v:
    case Rgb{+r, +g, +b}:
      lab.of(cbrt((0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b : F32)),
        cbrt((0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b : F32)),
        cbrt((0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b : F32)))

def rgb.of(+l: F32, +m: F32, +s: F32) -> Rgb:
  Rgb{(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s : F32),
    (0.0 - 1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s : F32),
    (0.0 - 0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s : F32)}

def cube(+x: F32) -> F32:
  (x * x * x : F32)

# OKLab to linear sRGB (may leave 0..1 outside the gamut; rgba clamps).
def oklab_to_linear(v: Lab) -> Rgb:
  match v:
    case Lab{+l, +a, +b}:
      rgb.of(cube((l + 0.3963377774 * a + 0.2158037573 * b : F32)),
        cube((l - 0.1055613458 * a - 0.0638541728 * b : F32)),
        cube((l - 0.0894841775 * a - 1.2914855480 * b : F32)))

# 0xRRGGBBAA to OKLab (alpha dropped).
def of_rgba(+c: U32) -> Lab:
  oklab(rgb(c))

# OKLab to 0xRRGGBBAA with this alpha byte.
def to_rgba(v: Lab, +alpha: U32) -> U32:
  rgba(oklab_to_linear(v), alpha)

def oklch(v: Lab) -> Lch:
  match v:
    case Lab{l, +a, +b}:
      Lch{l, F32.hypot(a, b), F32.atan2(b, a)}

def oklch_to_oklab(v: Lch) -> Lab:
  match v:
    case Lch{l, +c, +h}:
      Lab{l, (c * F32.cos(h) : F32), (c * F32.sin(h) : F32)}

# Interpolation
# -------------

# The colour weight of b for alpha bytes aa, ab at t (0 < t < 1). Colours
# are interpolated premultiplied (CSS Color 4): each colour counts in
# proportion to its alpha, so a transparent end lends no colour (fading red
# to transparent black stays red, without a dark fringe). Normalized by the
# mixed alpha this is t * ab / ((1 - t) aa + t ab); equal alphas give t.
def weight.go(same: Bool, +aa: U32, +ab: U32, +t: F32) -> F32:
  match same:
    case True{}:
      t
    case False{}:
      +wb = (t * U32.to_f32(ab) : F32)
      (wb / ((1.0 - t) * U32.to_f32(aa) + wb) : F32)

def weight(+aa: U32, +ab: U32, +t: F32) -> F32:
  weight.go(U32.is_eq(aa, ab), aa, ab, t)

# Alpha interpolated linearly, rounded.
def mix_alpha(+aa: U32, +ab: U32, +t: F32) -> U32:
  +fa = U32.to_f32(aa)
  F32.to_u32(F32.floor((fa + (U32.to_f32(ab) - fa) * t + 0.5 : F32)))

def lerp(+x: F32, +y: F32, +t: F32) -> F32:
  (x + (y - x) * t : F32)

def mix_lab(p: Lab, q: Lab, +s: F32) -> Lab:
  match p q:
    case Lab{+l0, +a0, +b0} Lab{+l1, +a1, +b1}:
      Lab{lerp(l0, l1, s), lerp(a0, a1, s), lerp(b0, b1, s)}

def mix_rgb(p: Rgb, q: Rgb, +s: F32) -> Rgb:
  match p q:
    case Rgb{+r0, +g0, +b0} Rgb{+r1, +g1, +b1}:
      Rgb{lerp(r0, r1, s), lerp(g0, g1, s), lerp(b0, b1, s)}

def mix_byte(+x: U32, +y: U32, +s: F32) -> U32:
  F32.to_u32(F32.floor((lerp(U32.to_f32(x), U32.to_f32(y), s) + 0.5 : F32)))

def oklab.go(+a: U32, +b: U32, +t: F32) -> U32:
  +aa = Color.alpha(a)
  +ab = Color.alpha(b)
  to_rgba(mix_lab(of_rgba(a), of_rgba(b), weight(aa, ab, t)), mix_alpha(aa, ab, t))

def linear.go(+a: U32, +b: U32, +t: F32) -> U32:
  +aa = Color.alpha(a)
  +ab = Color.alpha(b)
  rgba(mix_rgb(rgb(a), rgb(b), weight(aa, ab, t)), mix_alpha(aa, ab, t))

def srgb.go(+a: U32, +b: U32, +t: F32) -> U32:
  +aa = Color.alpha(a)
  +ab = Color.alpha(b)
  +s = weight(aa, ab, t)
  Color.pack(mix_byte(Color.red(a), Color.red(b), s), mix_byte(Color.green(a), Color.green(b), s),
    mix_byte(Color.blue(a), Color.blue(b), s), mix_alpha(aa, ab, t))

# a at t <= 0 (and NaN), b at t >= 1, exactly; t between mixes with `go`.
def ends(~go: @+a:U32 -> @+b:U32 -> @+t:F32 -> U32, above: Bool, below: Bool, +a: U32, +b: U32, +t: F32) -> U32:
  match above below:
    case False{} _:
      a
    case True{} False{}:
      b
    case True{} True{}:
      go(a, b, t)

# a to b at t in OKLab, premultiplied, alpha linear.
def mix_oklab(+a: U32, +b: U32, +t: F32) -> U32:
  ends(~oklab.go, (t > 0.0 : F32), (t < 1.0 : F32), a, b, t)

# a to b at t in linear light, premultiplied, alpha linear.
def mix_linear(+a: U32, +b: U32, +t: F32) -> U32:
  ends(~linear.go, (t > 0.0 : F32), (t < 1.0 : F32), a, b, t)

# a to b at t in encoded sRGB (bytes), premultiplied, alpha linear.
def mix_srgb(+a: U32, +b: U32, +t: F32) -> U32:
  ends(~srgb.go, (t > 0.0 : F32), (t < 1.0 : F32), a, b, t)
