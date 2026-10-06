# Examples

`shapes.bend` combines the standalone renderer with Ankra's window loop. It
shows rectangles, borders, circles, alpha composition, clipping, and retained
frames. A mouse-button press changes the accent color.

Use sibling directories named `Ankra` and `Chromi`. The renderer itself has no
Ankra dependency; only this example and `tests/ankra.bend` import it.

Validated with [Ankra `c94c8b5ff51f`](https://github.com/amage-si/ankra/commit/c94c8b5ff51f49c482a56e1894a741007bc542dd).
To reproduce the same dependency revision:

```sh
git -C ../Ankra checkout --detach c94c8b5ff51f49c482a56e1894a741007bc542dd
```

From the Chromi repository root:

```sh
export BEND_NO_TELEMETRY=1
mkdir -p build
bend tests/ankra.bend -o build/ankra-checks
./build/ankra-checks --threads 2 --gpu off
bend examples/shapes.bend -o build/shapes
./build/shapes --threads 2 --gpu off
```

The two companion checks exercise ordered close-event batches and dimension
bounds. They are headless checks, not a substitute for testing a real window.
The example uses CPU rendering and the official runtime's X11 presentation.
