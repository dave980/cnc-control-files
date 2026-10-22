# Commissioning log

Problems hit while bringing this machine up, and what actually fixed them.
Written down because most cost hours and several had misleading symptoms.

## Solved

### Spindle whined but would not turn at S24000

Miswired aviation connector between the VFD and the motor. Not a parameter.

### Endstops lit their LEDs but did not stop the axis

Several layers:

- Started with `:pu` on the input pins. The Doberman inputs are opto-isolated
  with onboard pull-ups, so the extra pull-up broke them. Removed.
- Sensors were marginal at first. 12 V was tried during debugging, but the
  `Switch Vcc` jumper is global and the tool changer needs 5 V, so they ended up
  back on 5 V — working reliably once the wiring and polarity were right.
- NPN-NO sensors need `:low`.

### `MSG:WARN: Limit switches do not support positive homing dir`

All three axes home positive (X right, Y back, Z up), so all use `limit_pos_pin`.

### Axes homed the wrong way

`positive_direction: true` for X, Y and Z. No direction pin is inverted.

### Vectric toolpaths went the wrong way

The X switch is on the **right** facing the front and Y's are at the back. Both
homed negative, so +X ran left and +Y ran toward the operator: correct CAM
orientation only when viewed from behind the machine. Fixed 2026-10-19 by
flipping both X and Y (homing `positive_direction: true`, switches on
`limit_pos_pin`, X and Y direction pins uninverted, every G53 X and Y in the
macros negated; same physical spots). An intermediate state flipped Y only,
which was mirrored. Now, facing the front: +X right, +Y away. In Vectric use
the **bottom-left** XY datum and zero at the stock's front-left corner.

### False X hard limit mid-job (2026-10-19)

Cutting at 18000 rpm, the machine alarmed with `Pn:X` at MPos X−639, far from
the X switch. The debug log showed the X input flicker 0 → 1 → 0. That is a
spurious signal, not a real trip. **Cause: a bad X sensor wire**, found and
fixed 2026-10-20; jobs run clean since. Same lesson as the Z endstop below:
check the connection before chasing EMI.

The spindle **kept running** through the alarm because `off_on_alarm` was
`false`. It is now `true`, so any alarm also stops the spindle.

### Hard limit triggered when starting the spindle

Looked like VFD noise coupling into the Z endstop wire in the drag chain, and a
lot of time went into shielding theories. It was **a loose wire on the Z
endstop**. Check connections before chasing EMI.

### Spindle would not run below S4000

Two separate causes, found in sequence:

1. No V/F boost at low frequency — fixed by the P00.07–P00.10 values in
   `vfd-yl620a.md`
2. A 60 Hz floor on the analog input — fixed by setting **P03.12 = 0**

After the first fix it ran at S1800 but at 48 Hz instead of 30. The second fix
brought commanded and actual into line.

### Engagement feed silently clamped

`tc.nc` asks for F2000 on the nut threading moves, but Z `max_rate_mm_per_min`
was 1500. FluidNC clamps without warning, so every tool change ran at 75 % of the
designed feed. Raised Z to 2500.

### `M6` did nothing — no motion, no error

The longest hunt here. The chain was verified piece by piece:

1. `$Message/Level` was below Info, hiding every diagnostic. Set to `Debug`.
2. With logging on, `M6 T1` showed `Current T:0 Selected T:1` and
   `Macro line: $SD/Run=tc.nc` — so the hook worked.
3. The status line read `SD:100.00,` with an **empty filename**. The job had
   completed instantly.

The macros were in **internal flash, not on an SD card**. `$SD/Run=` only looks at
the card and reports success when there is nothing there. Changed all three macro
paths to `$LocalFS/Run=`. Worked immediately.

Worth remembering: `$SD/Run=` failing silently is the trap. `SD:100.00` with no
filename means the file never ran.

### Y drifted slightly, unequally between sides

Both sides of the gantry drifted over repeated moves, by different amounts.

**Cause: the left rail was not parallel.** Fixed by loosening that rail's
mounting bolts and re-torquing them with the gantry bolted to both carriages, so
the gantry itself set the parallelism. No drift since.

This is the failure mode to expect on HGR20 profile rails. They have almost no
compliance, so two rails a tenth of a millimetre out of parallel bind the
carriages, both motors fight it, and the tighter side loses more — drift that is
shared but unequal. V-wheels would have flexed and absorbed it.

Things that turned out not to be the cause, for the record:

- Y/Y2 auto-squaring was fine — the homing log showed Y2 tripping ~0.018 mm
  before Y, so the gantry was square at home all along.
- The stepping engine name parses correctly; FluidNC matches enums
  case-insensitively, so `I2S_STream` is valid.
- Acceleration was never aggressive — 150 mm/s² with a 3000 mm/min rapid is
  0.33 s and 8 mm to reach full speed.
- The CL57T drivers are closed loop, so they correct position error rather than
  dropping steps silently. Worth remembering: when they *do* exceed their error
  limit they fault and assert ALM, which looks exactly like lost steps if ALM is
  not wired back to the controller.

### Z had no max_travel_mm

X and Y declared their travel but the Z block did not, so Z fell back to
FluidNC's default and the bottom of the axis had no soft limit. Z has only a
positive (top) limit switch, so soft limits are the *only* protection at the
bottom.

Measured from the home switch, **Z−118 puts the bottom of the carriage level
with the bottom of the rail** — past that the carriage starts to overhang the
rail end, which on a profile rail means the balls lose support and can escape.

`max_travel_mm: 115.000` is set from that, keeping a 3 mm buffer before any
overhang.

That leaves 10 mm of clearance below the Z−105 the tool changer plunges to. It
works, but it is the tightest margin on the machine — see `tool-changer.md`.

### Magazine pitch — settled

The 45.000 mm pitch and the Y85.400 base (Y−85.400 since the 2026-10-19 Y flip) are confirmed: all six pockets have
been exercised over repeated tool changes.

### Tool broken on the setter after the first M6 of a program

The macro handed control back with the spindle parked over the tool setter, and
the program's next line was `G0 Z0.8` — a work-coordinate Z move. The tool was
driven back down into the setter at rapid and broke, along with the setter.

The probe itself worked correctly; the light touch seen first was the probe
cycle doing its job.

Only the *first* tool change in a Vectric file is exposed, because that is the
only one where the post emits a Z move before an XY move. Hand-running `M6`
never reproduced it.

Fixed by having `tc.nc` and `measuretool.nc` return to their starting XY in
machine coordinates before finishing. Full write-up in `tool-changer.md`.

### VFD parameters dumped and cross-checked

`tools/vfd_dump.py` read all 192 addresses over the SH-U11F on COM3. P00.04
returned 4000, which validated the `Pgg.ii -> gg*256 + ii` mapping and the
0.1 Hz scaling independently rather than by inference.

Checked against the setup table PDF it corrected four values in
`vfd-yl620a.md` that had been copied from the PDF's suggested column rather
than read from the drive, confirmed P03.12 = 0 and P07.08 = 3 on the hardware,
and surfaced the P12.00 overload setting.

Getting the port open was the only real obstacle, and it was not the adapter:
COM5 was a Bluetooth virtual port, whose unanswered RFCOMM handshake is what
produces `error 121, semaphore timeout`. The adapter was COM3 all along.

### Spindle would not start after tightening the motor overload

`Err11`, motor overload. The dump showed P12.00 (rated motor current) at
15.0 A against a 6 A nameplate, so it was set to 6.0 A — and the spindle then
would not turn at all. 10.0 A failed too. Back at 15.0 A it runs.

The conclusion is that the drive's overload protection cannot be used on this
spindle: starting takes 13-19 A, the protection trips on that, and one
parameter governs both the starting allowance and the sustained limit. Full
reasoning in `vfd-yl620a.md`.

Tool changes verified again at 15.0 A, pickup and return, after the revert.
`vfd-parameters.md` is accurate as it stands, since the drive is back at the
value it was dumped with.

Worth recording as a method failure too. Three values were chosen by
arithmetic from the nameplate; two of them stopped the machine. The parameter
looked like a single threshold and is actually the scaling base for a group.

### The machine drove straight past a soft limit

Because soft limits were never on. `soft_limits` defaults to **false** on every
axis in FluidNC and the word did not appear anywhere in this config.

`max_travel_mm` alone does not constrain anything. It declares the geometry and
feeds the limit arithmetic, but nothing is enforced until the axis also carries
`soft_limits: true`. Having a travel figure in the file reads like protection
and is not.

Set on x, y and z, and uploaded to the controller on 2026-10-22. Worth
stating the second half: a value in `config.yaml` protects nothing until
`$CD` shows the controller actually holding it. That gap has cost real time
here before — see the `$SD/Run=` entry above.

#### What it does once enabled

Every G0/G1 line is checked before it is planned — `Cartesian::invalid_line()`
compares the **target** against the axis range and errors the whole line. Jogs
take a different path, `constrain_jog()`, which clamps the move instead.

The range comes out of homing rather than from `max_travel_mm` directly:

```
limitsMaxPosition = (positive_direction ? mpos : mpos + max_travel) + slop
```

With `mpos_mm: 0` and `positive_direction: true` on all three axes, the homed
corner is the maximum and travel runs negative:

| Axis | Range |
|---|---|
| X | -1220 to 0 |
| Y | -1200 to 0 |
| Z | -115 to 0 |

Which matches the table as built. All `G53` coordinates in the three macros
were checked against this envelope before enabling it — nothing was outside.

#### Jogs behave differently from program moves

This matters because the overrun that prompted all this was a jog.

A program move that would leave the envelope is **rejected whole** — the line
errors and nothing executes. A jog is **clamped**: it runs and simply stops at
the boundary. No alarm, nothing to clear, no error message. A jog that appears
to stop short has not failed, it has hit the fence.

If the machine is already **outside** the envelope, which it may well be right
after an overrun, the rules change again:

| Situation | Behaviour |
|---|---|
| Jogging further out, no switch active | move cancelled on that axis |
| Jogging further out, switch active | allowed, but capped at the pull-off distance |
| Jogging into the switch that guards that end | blocked |
| Jogging back toward the envelope | normal, unrestricted |

The pull-off is not set in this config, so it is FluidNC's default **1.0 mm** —
that is the most a single jog can move while outside the range. Enough to clear
a switch, not enough to get anywhere.

**Every one of those cases logs at `Debug` level and nothing higher.** At the
default message level a cancelled or clamped jog produces no output at all, so
it looks like the jog did nothing. This is the same trap that made the `M6`
hunt take as long as it did. Set `$Message/Level=Debug` before testing this and
the messages are explicit — "Soft limit violation on X", "Jog constrained to
axis range", "Jog amount limited when outside soft limits".

Homing first makes most of this moot, since the machine then starts inside the
envelope with a position it can trust.

#### What it still will not catch

- **Anything before `$H`.** The check compares against machine position, and
  unhomed that number is fiction. Soft limits are not a substitute for homing.
- **A wrong work offset inside the envelope.** This is the one worth
  remembering: the tool-setter crash drove to a perfectly legal machine Z. The
  limit is a machine-coordinate fence, and tool length offsets and work zero
  are what keep you off the spoil board — see `tool-changer.md`.
- **The move already running.** It rejects a line up front; it does not stop
  mid-move. A single long line that starts legal and ends illegal is refused
  entirely rather than part-executed.

## Open

### CL57T alarm outputs are not read by the controller

The four drivers have ALM outputs and nothing is connected to them. A driver
that exceeds its position-error limit faults and asserts ALM, and from the
controller's side that is indistinguishable from lost steps — which is exactly
the symptom that was chased above.

Plan is in `wiring.md`: `control: fault_pin: gpio.37:low`. The drivers have a
single ALM pin rather than a floating pair, so the four get paralleled and
there is no fail-safe series option — meter one driver idle and again under a
forced alarm to settle the polarity before wiring.

### The E-stop is not signalled to FluidNC

The hardwired switch cuts motor and spindle power but leaves the Doberman
running, so the controller keeps a stale position and nothing alarms. `$H`
after every E-stop is the workaround. `estop_pin` from a spare contact would
make it a real alarm. See `wiring.md`.

