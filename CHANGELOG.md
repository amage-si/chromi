# Changelog

All notable changes to Chromi are recorded here. Chromi follows
[semantic versioning](https://semver.org) in its 0.x form: while the API is
experimental, a minor version (0.2.0) may change it in breaking ways and a
patch version (0.1.1) only fixes. Chromi is built from source together with its
sibling AMAGE libraries; the set of versions tested together is listed in
[eco-build's releases](https://github.com/amage-si/eco-build/tree/main/releases).

## Unreleased

### Added

- `mix.bend`: colour interpolation for animations and gradients.
  `mix_oklab(a, b, t)`, `mix_linear` and `mix_srgb` mix two `0xRRGGBBAA`
  colours, premultiplied (CSS Color 4), alpha linear, exact at `t` 0 and 1,
  `t` clamped. Also the sRGB transfer function (`to_linear`, `to_srgb`,
  `byte_to_linear`, `linear_to_byte`), OKLab (`of_rgba`, `to_rgba`, `oklab`,
  `oklab_to_linear`) and OKLCH (`oklch`, `oklch_to_oklab`). Composition is
  unchanged (encoded sRGB).
- 9 native checks for it (82 in all) and `tests/mix_bench.bend`.

## [0.1.0] - 2026-10-09

First tagged release, tested with Bend 2.0.35 on Linux (X11/XWayland) as part
of AMAGE Eco 0.1.0.

### Included

- Canvas with rectangles, circles, rounded rectangles and borders,
  bitmaps, coverage masks, clips and straight-alpha composition.
- Draw lists, a CPU reference and a GPU path through Voltra, equal pixel for
  pixel.
- Retained frames with damage tracking: only changed parts are redrawn, and
  kept parts are drawn from Voltra's GPU store.
- The integrated demo (`examples/eco`): text, button, an editable text field
  with clipboard, PNG and SVG, accessible through Auvia, idle at zero wakeups.
- 73 native checks and 27 GPU checks (0 differing pixels).

[0.1.0]: https://github.com/amage-si/chromi/releases/tag/v0.1.0
