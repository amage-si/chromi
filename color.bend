import Base

# RGBA8, straight alpha. Blend in encoded sRGB, onto an opaque destination.
def red(c: U32) -> U32:
  (c >> 24n : U32)

def green(c: U32) -> U32:
  U32.and((c >> 16n : U32), 255)

def blue(c: U32) -> U32:
  U32.and((c >> 8n : U32), 255)

def alpha(c: U32) -> U32:
  U32.and(c, 255)

def pack(r: U32, g: U32, b: U32, a: U32) -> U32:
  U32.or(U32.or((r << 24n : U32), (g << 16n : U32)),
    U32.or((b << 8n : U32), a))

def channel(s: U32, d: U32, +a: U32) -> U32:
  ((s * a + d * (255 - a) + 127) / 255 : U32)

def over(+src: U32, +dst: U32) -> U32:
  +a = alpha(src)
  pack(channel(red(src), red(dst), a), channel(green(src), green(dst), a),
    channel(blue(src), blue(dst), a), 255)

def coverage(+ink: U32, value: U32) -> U32:
  U32.or(U32.and(ink, 4294967040), ((alpha(ink) * value + 127) / 255 : U32))
