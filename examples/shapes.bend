import Base
import ../main.bend as C
import ../geometry.bend as G
import ../../Ankra/main.bend as A

def draw(+counter: U32) -> Result<&1, &1, U32 & String, Image>:
  +accent = Bool.pick(U32, U32.is_eq((counter % 2 : U32), 0), 1089715967, 4288766719)
  c = C.new(640, 420, 1.0, 219422463)
  c = C.fill_rect(c, G.Rect{24.0, 24.0, 592.0, 372.0}, 354033919)
  c = C.fill_rect(c, G.Rect{48.0, 50.0, 120.0, 6.0}, accent)
  c = C.fill_rect(c, G.Rect{48.0, 86.0, 250.0, 122.0}, 555886591)
  c = C.stroke_rect(c, G.Rect{48.0, 86.0, 250.0, 122.0}, 2.0, 1078740735)
  c = C.circle(c, 133.0, 146.0, 38.0, accent)
  c = C.circle(c, 181.0, 146.0, 38.0, 4284311936)
  c = C.clip_rect(c, G.Rect{328.0, 86.0, 264.0, 122.0})
  c = C.fill_rect(c, G.Rect{328.0, 86.0, 264.0, 122.0}, 270611711)
  c = C.circle(c, 378.0, 146.0, 75.0, 1759685375)
  c = C.circle(c, 524.0, 146.0, 75.0, 1089715967)
  c = C.reset_clip(c)
  c = C.fill_rect(c, G.Rect{48.0, 246.0, 544.0, 126.0}, 270611711)
  c = C.fill_rect(c, G.Rect{68.0, 266.0, 504.0, 6.0}, accent)
  c = C.fill_rect(c, G.Rect{68.0, 290.0, 328.0, 6.0}, 943805439)
  c = C.fill_rect(c, G.Rect{68.0, 314.0, 224.0, 6.0}, 943805439)
  c = C.fill_rect(c, G.Rect{68.0, 338.0, 404.0, 6.0}, 943805439)
  C.finish(c)

def changes(events: List<&2, Event>, count: U32) -> U32:
  match events:
    case Nil{}:
      count
    case Mouse{x, y, b, True{}} <> rest:
      changes(rest, (count + 1 : U32))
    case _ <> rest:
      changes(rest, count)

def redraw(same: Bool, +state: U32) -> IO(A.Step<U32>):
  match same:
    case True{}:
      IO.pure(A.Step<U32>, A.Keep{state})
    case False{}:
      do IO<A.Step<U32>>:
        image : Image <- IO.try(Image, IO.pure(Result<&1, &1, U32 & String, Image>, draw(state)))
        IO.print("shapes redraw=" ++ U32.show(state))
        return A.Redraw{state, image}

def tick(batch: A.Batch, state: U32) -> IO(A.Step<U32>):
  A.Batch{closed, count, events} = batch
  +current = state
  +next = changes(events, current)
  redraw(U32.is_eq(next, current), next)

def main() -> IO(Unit):
  do IO<Unit>:
    image : Image <- IO.try(Image, IO.pure(Result<&1, &1, U32 & String, Image>, draw(0)))
    IO.print("CPU diagnostic shapes; click changes colour; WM close releases the window")
    A.run(~U32, ~tick, "AMAGE Eco - Chromi CPU shapes", 640, 420, 3600n, 0, image)
    IO.print("shapes closed")
