# Chromi: instructions for contributors and agents

Chromi is the 2D rendering and composition layer of the AMAGE UI ecosystem,
implemented in **Bend 2**. Read the README for current capabilities and limits;
a roadmap item is not implemented merely because it appears in the project scope.

## Implementation

- Implement library logic in Bend 2, rather than wrapping an equivalent toolkit
  written in another language.
- The official Bend compiler/runtime, OS APIs, and drivers remain external
  dependencies. Chromi has no native code: the GPU path goes through Voltra,
  windows through Ankra.
- The CPU reference (`replay.bend`) and Voltra's shader share integer rules
  (coverage, tint, blending). Change them together and keep `gpu_tests.bend`
  at 0 differing pixels; the CPU path stays the reference renderer.
- Before writing Bend, run `bend version` and read `bend guide` from the installed
  toolchain. Verify available syntax/effects instead of assuming old examples work.
- Keep source, comments, documentation, and commit messages in English.

## Writing fast Bend

Correct Bend is not fast Bend by default. Measured rules (Bend 2.0.35):

- Indexed, large or hot data (bytes, pixels, coverage, quads) lives in an
  `Array<U32>` (native flat block, ~1 ns/read), not a `List`. Lists are fine
  when tiny, built once and consumed in order. Arrays are affine and cannot be
  fields of `Data` types: keep them local and convert once at the boundary.
- No `do Result`/`do Maybe` binds or callbacks per byte, pixel or glyph: each
  bind is a closure (45% of a measured profile). Thread state through one
  recursive def that matches on the result.
- `||`, `&&` and `Bool.pick` evaluate both sides; use `match` to stop early.
- Never `Array.clone` or append (`List.append`) in a loop; build with a
  reversed accumulator or a tail parameter.
- A parameter that a def only matches or passes to itself is borrowed (no
  refcount); descend trees with the selector as a parameter.
- Keep non-recursive records small (they are passed flattened; the widest one
  widens every call frame). Box big ones with an `Alias{x: T}` constructor.
- Split independent, balanced work of tens of µs or more with a parallel call
  (`a b = f(l) g(r)`); never parallelize tiny or IO-bound work.
- Measure before and after on the same input; print a result before the next
  `IO.now()`.

Here: per-frame work must stay proportional to the damage. Prefer
`Fr.stamped` for content whose stamp proves it unchanged. Cached quad words are
lists because `Part` is `Data`; that per-frame copy is known debt (a persistent
GPU slot per part is the real fix). The CPU quadtree painter's four quadrants
are independent and the natural place for a parallel split.

## Linux first

The initial goal is excellent behavior on Ian's actual Linux development machine:
correctness, stability, measured performance, and a finished user experience.
Inspect the effective environment before choosing integrations.

Build compatibility layers as the project progresses, after visible, well-made
Linux results. Do not let speculative Windows or macOS abstractions delay local
quality. Introduce abstractions from concrete needs.

## Working practice

- Preserve existing work and keep the library's boundary clear.
- Favor simple, maintainable code. Pursue fast, polished behavior with evidence.
- Run relevant native checks after changes. Validate affected visual interactions
  on a real window when changing visible behavior, then close the window.
  Capture only the window being tested (its toplevel, never a screen region);
  the helpers in `tools/` do that and do not take keyboard focus.
- Compilation is not visual proof. Runtime checks are not proofs of the entire
  system. State partial support and unverified behavior explicitly.
- Build sequentially. Do not impose virtual-address limits on the Bend runtime
  or suppress crash reporting. Investigate failures before retrying.
- Keep generated binaries, logs, crash dumps, credentials, and machine-specific
  evidence out of Git. Stage explicit paths and preserve concurrent changes.

See [CONTRIBUTING.md](CONTRIBUTING.md) for validation commands.
