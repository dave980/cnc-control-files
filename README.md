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
| Ball screws | 1605 (5 mm pitch) |
| Axes | X, Y1, Y2 (auto-squaring gantry), Z |
| Endstops | ROURCK SN04-N inductive, NPN-NO, run at 5 V |
| Spindle | HLTNC GDZ80X73-2-2, 2.2 kW air cooled, 24000 rpm / 400 Hz |
| VFD | YL620-A |
| Tool changer | RapidChange linear magazine Premium, 6 pockets, ER20 |

Travel: X 1220 mm, Y 1180 mm.

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
```

## Installation

Macros live in the controller's **internal flash**, not on an SD card. This matters —
`$SD/Run=` silently reports success and does nothing when the file isn't on a card.

1. Upload `config/config.yaml` and the three `.nc` files via the FluidNC web UI
2. `$Bye` to restart
3. `$LocalFS/List` — confirm `tc.nc`, `measuretool.nc`, `findzposition.nc` are present
4. `$CD` — confirm the config loaded

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
