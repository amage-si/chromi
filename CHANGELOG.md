# Changelog

All notable changes to Chromi are recorded here. Chromi follows
[semantic versioning](https://semver.org) in its 0.x form: while the API is
experimental, a minor version (0.2.0) may change it in breaking ways and a
patch version (0.1.1) only fixes. Chromi is built from source together with its
sibling AMAGE libraries; the set of versions tested together is listed in
[eco-build's releases](https://github.com/amage-si/eco-build/tree/main/releases).

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
