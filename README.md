# CNC Mill — Doberman / FluidNC / RapidChange ATC

Working configuration and commissioning notes for a 3-axis CNC mill (X, Y1, Y2, Z)
running FluidNC on a Doberman board, with a YL620-A VFD spindle and a RapidChange
linear magazine automatic tool changer.

Everything here is the as-built state of a machine that homes, cuts and changes
tools. Values were measured on the machine, not copied from a template.

## Machine

| Item | Detail |
|---|---|
| Controller | Doberman CNC Board (Bart Dring), ESP32-S3, FluidNC |
| Motors | NEMA 24, 5.0 A, 3 N·m — StepperOnline 24E1K-30 |
| Drivers | CL57T v4.0 closed loop |
| Motor supply | 48 V |
| Logic supply | 12 V |
| Rails | HGR20 throughout — X and Y 1500 mm, Z 300 mm with HGH20CA blocks |
| Ball screws | 1605, 5 mm pitch — X/Y RM1605 1500 mm, Z SFU1605 350 mm, BK12/BF12 supports |
| Axes | X, Y1, Y2 (auto-squaring gantry), Z |
| Endstops | ROURCK SN04-N inductive, NPN-NO, run at 5 V |
| Spindle | HLTNC GDZ80X73-2-2, 2.2 kW air cooled, 24000 rpm / 400 Hz |
| VFD | YL620-A |
| Tool changer | RapidChange linear magazine Premium, 6 pockets, ER20 |

Travel: X 1220 mm, Y 1200 mm, Z 115 mm. Z is tight — `tc.nc` reaches −105, so
there is 10 mm to spare.

At the bottom of Z travel the bare spindle nose sits 25 mm above the spoil
board, so with an ER20 nut and a tool fitted the tip reaches the board well
before the soft limit. **The Z soft limit does not protect the spoil board** —
tool length offsets and work zero do. `docs/tool-changer.md` has the full Z
geometry and the −90 clearance plane over the magazine.

## Layout

```
config/config.yaml              FluidNC machine config
macros/tc.nc                    M6 tool change
macros/measuretool.nc           macro0 — measure current tool
macros/findzposition.nc         macro1 — find IR beam Z position
docs/wiring.md                  pin assignments and the reasoning behind them
docs/vfd-yl620a.md              VFD parameters and speed calibration
docs/tool-changer.md            ATC coordinates, sequence, recovery
docs/troubleshooting.md         problems hit during commissioning and what fixed them
docs/deploying.md               getting files onto the controller
tools/deploy.sh                 upload config and macros over the network
tools/deploy.ps1                the same, for Windows PowerShell
tools/deploy.cmd                double-clickable launcher for the above
```

## Installation

Macros live in the controller's **internal flash**, not on an SD card. This matters —
`$SD/Run=` silently reports success and does nothing when the file isn't on a card.

Either through the FluidNC web UI, or over the network:

```
./tools/deploy.sh <board-ip> --restart
```

Then confirm:

1. `$LocalFS/List` — `tc.nc`, `measuretool.nc`, `findzposition.nc` present
2. `$CD` — the config loaded

See `docs/deploying.md`. There is no direct GitHub-to-board path; the upload has
to come from a machine on the same network.

## Daily startup

```
$H              home — Z first, then XY with Y/Y2 auto-squaring
M61 Q<n>        tell FluidNC what is in the spindle (Q0 if empty)
```

`M61` is not optional. FluidNC sets `current_tool = -1` on every restart, and `tc.nc`
aborts with an alarm when it sees a negative tool number. `$H` does not fix this —
homing knows about position, not about what is in the spindle.

## Current state

Working:

- Homing on all axes, Y/Y2 auto-squaring
- Spindle across the full range, including tool-change speeds
- M6 tool change — load, unload, IR beam verification, tool setter touch-off
- Magazine geometry verified at pockets 1 and 6
- Y position holds — the left rail was out of parallel; loosened and re-torqued

Not fitted:

- **Dust cover** — physically removed from the magazine. It is servo driven
  through an ATtiny and never responded to a 5 V logic signal, so it is out of
  the config and out of the macros. See `docs/tool-changer.md`.
