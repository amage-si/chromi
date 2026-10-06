import Base
import ../../scene.bend as S
import ../../replay.bend as R
import ./ui.bend as U
import ./media.bend as Media
import ../../../Runika/font.bend as F

# Writes the integrated demo's first frame, painted by Chromi's CPU
# reference renderer (replay.bend), as a binary PPM:
#   build/eco-reference-<w>x<h>.ppm   (default 900x560; `reference W H`)
# A capture of the GPU-presented window at the same size, before any
# input, must equal it pixel for pixel. Run from the Chromi directory.

def bytes(n: Nat, r: Array<U32> & U32, +i: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n:
      acc
    case 1n+p:
      (a, +c) = r
      +j = (i - 1 : U32)
      bytes(p, Array.get(U32, a, j), j,
        (c >> 24n : U32) <> ((c >> 16n) .&. 255 : U32) <> ((c >> 8n) .&. 255 : U32) <> acc)

def write.done(r: File & Result<&1, &1, U32 & String, Unit>, path: String) -> IO(Unit):
  (f, ok) = r
  do IO<Unit>:
    File.close(f)
    IO.print("wrote " ++ path)

def write.body(r: File & Result<&1, &1, U32 & String, Unit>, pixels: List<&2, U32>, path: String) -> IO(Unit):
  (f, ok) = r
  do IO<Unit>:
    r2 : File & Result<&1, &1, U32 & String, Unit> <- File.write_bytes(f, pixels)
    write.done(r2, path)

def write(+w: U32, +h: U32, px: Array<U32>) -> IO(Unit):
  +n = (w * h : U32)
  +path = "build/eco-reference-" ++ U32.show(w) ++ "x" ++ U32.show(h) ++ ".ppm"
  +rgb = bytes(U32.to_nat(n), Array.get(U32, px, (n - 1 : U32)), (n - 1 : U32), [])
  do IO<Unit>:
    f : File <- IO.try(File, File.open(path, "w"))
    r1 : File & Result<&1, &1, U32 & String, Unit> <- File.write(f,
      "P6\n" ++ U32.show(w) ++ " " ++ U32.show(h) ++ "\n255\n")
    write.body(r1, rgb, path)

def need(-A: Data, r: Result<&2, &2, String, A>) -> IO(A):
  match r:
    case Fail{message}:
      IO.die(A, 1, message)
    case Done{x}:
      IO.pure(A, x)

type Size is Data:
  Size{width: U32, height: U32}

def number(+s: String, +fallback: U32) -> U32:
  Maybe.default(&2, U32, U32.read(s), fallback)

# `reference W H`, defaulting to 900x560.
def size(args: List<String>) -> Size:
  match args:
    case Con{prog, Con{+w, Con{+h, rest}}}:
      Size{number(w, 900), number(h, 560)}
    case _:
      Size{900, 560}

def render(+font: F.Font, +picture: Media.Picture, +heart: List<&2, Media.Shape>, s: Size) -> IO(Unit):
  Size{+w, +h} = s
  do IO<Unit>:
    +model : U.Model <- need(U.Model, U.build(U.Assets{font, picture, heart}, w, h))
    +t0 : Nat <- IO.now()
    px : Array<U32> <- IO.pass(Array<U32>, R.pixels(U.frame(model)))
    +t1 : Nat <- IO.now()
    IO.print("CPU reference frame " ++ U32.show(w) ++ "x" ++ U32.show(h) ++ ": " ++
      U32.show(S.count(U.frame(model))) ++ " operations painted in " ++ Nat.show(Nat.sub(t1, t0)) ++ " ms")
    write(w, h, px)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    loaded : Result<&2, &2, String, F.Font> <- F.load("/usr/share/fonts/liberation/LiberationSans-Regular.ttf")
    +font : F.Font <- need(F.Font, loaded)
    +picture : Media.Picture <- Media.png("/usr/share/pixmaps/kitty.png")
    +heart : List<&2, Media.Shape> <- Media.svg("../Splina/fixtures/heart-fill.svg", U.heart_color(), 96.0)
    render(font, picture, heart, size(args))
