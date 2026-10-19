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

## Positions — not measured yet

Both macros carry the same four positions at the top, in G53 machine
coordinates. Both ship with `ds_park_x = 0`, and **while it is 0 they alarm
and refuse to run**.

| Parameter | What it is |
|---|---|
| `ds_park_x`, `ds_park_y` | Spindle XY with the shoe slid fully home on the stand |
| `ds_clear_x`, `ds_clear_y` | Spindle XY in line with the stand rails, shoe completely off the flanges. Must differ from park only along the slot direction |
| `ds_engage_z` | Spindle Z with the shoe on and its slot level with the flanges |
| `ds_lift` | Distance to pull straight up to break the magnets (15 mm default) |

### Measuring them

1. Home. Fit the shoe to the spindle by hand. Put **no tool or a short tool** in the collet.
2. Jog at low speed until the shoe sits fully home on the stand. Record MPos as park X/Y and engage Z.
3. Jog along the slot direction only until the shoe is fully off the flanges, plus about 10 mm. Record that X/Y as clear.
4. Enter the same numbers in **both** files, then run `tools/deploy`.
5. The first run uses feed override at 25% with a hand on feed hold.

## Hazards

- **Running load with the shoe already on drives it into the stand.** Nothing
  senses the shoe, so load stops on `M0` and asks a person to check. Unload has
  no such check. Running it with no shoe fitted just slides the bare plate past
  the stand.
- **Tool stick-out.** During both macros the tool sits inside the shoe at
  engage Z. A long tool can reach the stand's base plate. Unload with a short
  tool or none until the clearance has been checked.
- **Tool changes.** The brushes hang below the nose, and `tc.nc` drives Z to
  −105 into the magazine. The shoe must be parked before any `M6`. The macros
  are not yet called from `tc.nc`.

## Not done yet

- Calling unload/load automatically from `tc.nc`. FluidNC would have to run
  a file from inside `tc.nc`, which is already running from inside the job,
  and that nesting is untested on this board. The fallback is to inline the
  moves into `tc.nc`.
