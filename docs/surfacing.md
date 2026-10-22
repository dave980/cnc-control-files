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
| `--tool-dia` | 25.4 | **Measure it.** Nothing on the machine knows this — see below |
| `--corner-radius` | 0 | Insert corner radius. Limits how wide the stepover can go |
| `--stepover` | 0.4 | Fraction of diameter. Lower for a better finish, longer run |
| `--doc` | 0.5 | Max per depth pass |
| `--feed` | 2000 | Z `max_rate_mm_per_min` is 2500, X/Y 3000 — do not exceed those |
| `--rpm` | 15000 | |
| `--safe-z` | 5.0 | Above work zero |
| `--park X Y` | — | Machine coordinates to finish at, emitted as `G53` |

## Nothing on the machine knows the tool diameter

FluidNC has no tool table. `M61` records which tool *number* is in the spindle
and the setter measures its *length* — and that is the whole of what the
controller knows about a tool. Diameter appears nowhere, so it cannot be looked
up or inferred, and `--tool-dia` is simply believed.

Get it wrong and the error is quiet: the overhang and the stepover are both
derived from it, so a diameter set larger than the real cutter leaves uncut
strips between passes and a short margin at the edges. Measure the cutter, do
not trust the listing it was bought under.

## The other radius: insert corners

A surfacing cutter's inserts are rounded at the corners, so the genuinely flat
part of its cut is `tool_dia - 2R`, not the full diameter. While adjacent
passes overlap within that flat width there is no ridge at all. Past it the
overlap falls on the corner arc and leaves a scallop, and past the arc entirely
the cutter cannot reach and material is simply left behind.

Pass `--corner-radius` and the script works this out. For a 25.4 mm cutter with
0.8 mm inserts the flat is 23.80 mm:

| Stepover | Ridge |
|---|---|
| 0.90 (22.86 mm) | none — flats still overlap |
| 0.94 (23.88 mm) | 1 micron |
| 0.96 (24.38 mm) | 55 microns |
| 0.98 (24.89 mm) | 215 microns |
| 1.00 (25.40 mm) | refused — periphery cannot reach |

The default 0.4 stepover is nowhere near this limit, so for normal use the
corner radius changes nothing. It matters if you are pushing the stepover up to
shorten a long job, which is exactly when tramlines appear and the cause is not
obvious.

## Before running it

- `$H` first. Soft limits mean nothing unless the machine knows where it is.
- Check the printed span against your work zero. The program cannot.
- Dry run above the work: set Z zero high, or raise `--safe-z` and watch the
  first pass before committing to the real depth.
- Feeds above the axis maximums are silently clamped by FluidNC — the same
  trap that had every tool change running at 75 % of its intended feed.
