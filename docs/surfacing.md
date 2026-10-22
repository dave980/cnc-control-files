# Surfacing a board

`tools/surface.py` writes a flattening program. Metric, work coordinates, G54.

```
python tools/surface.py --length 400 --width 300 --depth 1.5 -o surface.nc
```

`--length` is X, `--width` is Y, `--depth` is how much material comes off in
total. Everything else has a default.

## Setting up

**Work zero goes at the front-left corner of the board, Z0 on the surface you
are cutting down from.** The board then runs +X to the right and +Y toward the
back, which matches the machine after the axis flip.

Z0 is the *existing* surface, not the finished height — the program removes
`--depth` from wherever you zero.

The summary printed after generating gives the span the cutter centre covers,
including the overhang. Check that against where you set zero: the machine
envelope is X -1220..0, Y -1200..0, Z -115..0, and the program is in work
coordinates so nothing in it knows where the board is.

## What it generates

- Raster passes along X, stepping over in Y, alternating direction.
- The cutter **overhangs every edge** by its radius plus `--lead`, so the whole
  surface is cut and nothing is left proud at the boundary.
- The plunge happens off the corner of the board, in air, never into material.
- Depth is split into equal passes no deeper than `--doc`, so asking for 1.5 mm
  at the default 0.5 gives three passes of exactly 0.5.
- Stepover is distributed evenly rather than leaving a thin final pass: a
  300 mm width with a 10.16 mm maximum becomes 30 passes of exactly 10.0.

Coverage is verified geometrically, not assumed — the generated path was
checked against a 0.5 mm grid over the full board area with no uncovered
points.

## Options worth changing

| Option | Default | Note |
|---|---|---|
| `--tool-dia` | 25.4 | A surfacing cutter. Set this honestly; coverage depends on it |
| `--stepover` | 0.4 | Fraction of diameter. Lower for a better finish, longer run |
| `--doc` | 0.5 | Max per depth pass |
| `--feed` | 2000 | Z `max_rate_mm_per_min` is 2500, X/Y 3000 — do not exceed those |
| `--rpm` | 15000 | |
| `--safe-z` | 5.0 | Above work zero |
| `--park X Y` | — | Machine coordinates to finish at, emitted as `G53` |

## Before running it

- `$H` first. Soft limits mean nothing unless the machine knows where it is.
- Check the printed span against your work zero. The program cannot.
- Dry run above the work: set Z zero high, or raise `--safe-z` and watch the
  first pass before committing to the real depth.
- Feeds above the axis maximums are silently clamped by FluidNC — the same
  trap that had every tool change running at 75 % of its intended feed.
