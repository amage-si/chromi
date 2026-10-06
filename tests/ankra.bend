import Base
import ../../Ankra/main.bend as A

# Companion checks for the Ankra window demo. Core renderer tests are standalone.
def check(ok: Bool, name: String) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("PASS " ++ name)
    case False{}:
      IO.die(Unit, 1, "FAIL " ++ name)

def events(batch: A.Batch) -> Bool:
  match batch:
    case A.Batch{True{}, count, Move{x, y} <> Close{} <> Nil{}}:
      U32.is_eq(count, 2) && U32.is_eq(x, 3) && U32.is_eq(y, 4)
    case _:
      False{}

def main() -> IO(Unit):
  do IO<Unit>:
    check(events(A.collect([Move{3, 4}, Close{}])), "ordered event batch and close")
    check(Bool.not(A.valid_size(0, 20)) && A.valid_size(4096, 4096), "window bounds")
    IO.print("2 Ankra companion checks passed")
