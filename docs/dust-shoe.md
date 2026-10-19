# Dust shoe — load / unload

The shoe is two pieces. The upper plate with the hose port stays on the
spindle. The lower brush section is held to it by magnets and parks in a
printed stand bolted to the spoil board. The stand has two uprights whose top
flanges run in the slot along the side of the shoe.

- **Unload** (`macros/dustshoe_unload.nc`, WebUI macro button 2): at the
  slot's height, slide the shoe sideways onto the stand flanges, then pull
  the spindle straight up. The flanges hold the shoe down and the magnets
  let go.
- **Load** (`macros/dustshoe_load.nc`, WebUI macro button 3): come down
  slowly over the parked shoe until the magnets seat, then slide it back off
  the flanges.

CAD and STLs are in `cad/dust-shoe/`.

## Positions

G53 machine coordinates, given by Dave on 2026-10-19:

| Point | X | Y | Z |
|---|---|---|---|
| Lead-in (shoe on, clear of the stand) | 1210.000 | 730.000 | −90.000 |
| Parked (shoe fully home on the stand) | 1210.000 | 610.000 | −90.000 |

The shoe slides along Y at X1210, 120 mm from Y730 to Y610 at F1000. Coming
out it is the reverse.
Breaking the magnets is a 15 mm pull from Z −90 to −75 at F300, then a rapid
to Z0. Picking up is a rapid to Z −75 and a slow F300 descent to −90.

These numbers are in **three places**: `macros/tc.nc`, `macros/dustshoe_unload.nc`
and `macros/dustshoe_load.nc`. Change all three together.

## In the tool change

`tc.nc` now parks the shoe right after the IR-beam check and before anything
else moves. It picks the shoe back up after the tool-setter touch-off, then
returns to the starting XY. So every real `M6` does: shoe off → unload old tool
→ load new tool → measure → shoe on. An M6 for the tool already loaded is
bypassed and does not touch the shoe. The moves are inlined rather than
calling the standalone files, because running a file from inside `tc.nc`
(itself running inside the job) is untested on this board.

`tc.nc` assumes the shoe is **on the spindle** when an M6 starts. If it isn't,
unload slides the bare plate past the stand, which is harmless, and load then
picks the shoe up.

## Standalone macros

For parking or fitting the shoe outside a tool change. Load stops on `M0`
first and asks a person to confirm the shoe is in the stand. Running it with
the shoe already on would drive the shoe into the stand.

## Hazards

- **Long tools.** At Z −90 the tool sits inside the shoe and passes over the
  stand's base plate. Check stick-out against the stand on the first run.
- **Path at Z −90.** The shoe moves X1210, from Y730 to Y610, beside the
  magazine (pockets run Y85–310 at X1211.4). Keep that space clear.
- **`measuretool.nc` (macro button 0) does not remove the shoe.** It probes
  from Z0 down to −75 over the setter with the brushes hanging below the nose.
  Park the shoe first with macro button 2.

## First run

Do a dry run with feed override at 25% and a hand on feed hold. Run unload
(button 2), then load (button 3), then an `M6` between two tools.
