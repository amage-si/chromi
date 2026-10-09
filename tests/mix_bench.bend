import Base
import ../color.bend as Color
import ../mix.bend as M

# Colour interpolation: the full sRGB -> OKLab -> sRGB round trip and the cost
# of one mix. Build and run with the bench lock held:
#   bend tests/mix_bench.bend -o build/mix_bench
#   flock /tmp/amage-eco-bench.lock build/mix_bench

def diff(+x: U32, +y: U32) -> U32:
  (U32.max(x, y) - U32.min(x, y) : U32)

def channel_error(+c: U32, +d: U32) -> U32:
  U32.max(U32.max(diff(Color.red(c), Color.red(d)), diff(Color.green(c), Color.green(d))),
    U32.max(diff(Color.blue(c), Color.blue(d)), diff(Color.alpha(c), Color.alpha(d))))

# Every opaque colour: the worst channel error in the top byte, the number of
# colours that do not come back exactly below it.
def round_trip(n: Nat, +i: U32, +worst: U32, +off: U32) -> U32:
  match n:
    case 0n:
      ((worst << 24n) + off : U32)
    case 1n+p:
      +c = ((i << 8n) .|. 255 : U32)
      +e = channel_error(c, M.to_rgba(M.of_rgba(c), 255))
      round_trip(p, (i + 1 : U32), U32.max(worst, e), (off + U32.min(e, 1) : U32))

def a_of(+i: U32) -> U32:
  (i * 2654435761 : U32)

def b_of(+i: U32) -> U32:
  (i * 40503 + 12345 : U32)

def t_of(+i: U32) -> F32:
  (U32.to_f32((i % 1000 : U32)) / 1000.0 : F32)

# The loop and the inputs alone, to subtract.
def none(n: Nat, +i: U32, +acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+p:
      none(p, (i + 1 : U32), (acc .^. a_of(i) .^. b_of(i) .^. F32.to_u32(t_of(i)) : U32))

def oklab(n: Nat, +i: U32, +acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+p:
      oklab(p, (i + 1 : U32), (acc .^. M.mix_oklab(a_of(i), b_of(i), t_of(i)) : U32))

def linear(n: Nat, +i: U32, +acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+p:
      linear(p, (i + 1 : U32), (acc .^. M.mix_linear(a_of(i), b_of(i), t_of(i)) : U32))

def srgb(n: Nat, +i: U32, +acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+p:
      srgb(p, (i + 1 : U32), (acc .^. M.mix_srgb(a_of(i), b_of(i), t_of(i)) : U32))

def main() -> IO(Unit):
  do IO<Unit>:
    +t0 : Nat <- IO.now()
    +r : U32 = round_trip(16777216n, 0, 0, 0)
    IO.print("round trip of all 16,777,216 opaque colours: worst channel error " ++ U32.show((r >> 24n : U32)) ++
      ", colours not exact " ++ U32.show((r .&. 16777215 : U32)))
    +t1 : Nat <- IO.now()
    IO.print("  " ++ Nat.show(Nat.sub(t1, t0)) ++ " ms")
    IO.print("loop alone (checksum " ++ U32.show(none(1000000n, 0, 0)) ++ ")")
    +t2 : Nat <- IO.now()
    IO.print("1M mix_oklab (checksum " ++ U32.show(oklab(1000000n, 0, 0)) ++ ")")
    +t3 : Nat <- IO.now()
    IO.print("1M mix_linear (checksum " ++ U32.show(linear(1000000n, 0, 0)) ++ ")")
    +t4 : Nat <- IO.now()
    IO.print("1M mix_srgb (checksum " ++ U32.show(srgb(1000000n, 0, 0)) ++ ")")
    +t5 : Nat <- IO.now()
    IO.print("ns per call: loop " ++ Nat.show(Nat.sub(t2, t1)) ++ ", oklab " ++ Nat.show(Nat.sub(t3, t2)) ++
      ", linear " ++ Nat.show(Nat.sub(t4, t3)) ++ ", srgb " ++ Nat.show(Nat.sub(t5, t4)) ++ " (ms per million)")
