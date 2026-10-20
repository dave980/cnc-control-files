# Dust shoe — load / unload

The shoe is two pieces. The upper plate with the hose port stays on the
spindle. The lower brush section is held to it by magnets and parks in a
printed stand bolted to the spoil board. The stand has two uprights whose top
flanges run in the slot along the side of the shoe.

- **Unload** (`macros/dustshoe_unload.nc`, config `macro2`): at the
  slot's height, slide the shoe sideways onto the stand flanges, then pull
  the spindle straight up. The flanges hold the shoe down and the magnets
  let go.
- **Load** (`macros/dustshoe_load.nc`, config `macro3`): come down
  slowly over the parked shoe until the magnets seat, then slide it back off
  the flanges.

CAD and STLs are in `cad/dust-shoe/`.

## Positions

G53 machine coordinates, given by Dave on 2026-10-19 (Z corrected from −90 to −87.5 the same day):

| Point | X | Y | Z |
|---|---|---|---|
| Lead-in (shoe on, clear of the stand) | −1210.000 | −730.000 | −87.500 |
| Parked (shoe fully home on the stand) | −1210.000 | −610.000 | −87.500 |

The shoe slides along Y at X−1210, 120 mm from Y−730 to Y−610 at F1000. Coming
out it is the reverse.
Breaking the magnets is a 15 mm pull from Z −87.5 to −72.5 at F300, then a rapid
to Z0. Picking up is a rapid to Z −72.5 and a slow F300 descent to −87.5.

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

`macro2` and `macro3` in `config.yaml` are FluidNC's numbered macros, not WebUI
buttons. Run them from the console with `$Macros/Run=2` (park) and
`$Macros/Run=3` (pick up), or call the files directly with
`$LocalFS/Run=dustshoe_unload.nc` / `dustshoe_load.nc`. To get an on-screen
button, add a WebUI macro whose command is one of those lines. A physical
button would need a free input pin, and gpio.37 is reserved for the driver
alarms.

For parking or fitting the shoe outside a tool change. Load stops on `M0`
first and asks a person to confirm the shoe is in the stand. Running it with
the shoe already on would drive the shoe into the stand.

## Hazards

- **Long tools.** At Z −87.5 the tool sits inside the shoe and passes over the
  stand's base plate. Check stick-out against the stand on the first run.
- **Path at Z −87.5.** The shoe moves X−1210, from Y−730 to Y−610, beside the
  magazine (pockets run Y−85 to −310 at X−1211.4). Keep that space clear.
- **`measuretool.nc` (config `macro0`) does not remove the shoe.** It probes
  from Z0 down to −75 over the setter with the brushes hanging below the nose.
  Park the shoe first with `$Macros/Run=2`.

## Status

Tested working on 2026-10-19 after the X/Y flip, both inside an `M6` and on its own.
