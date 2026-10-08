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

Z homes up, so it needs `limit_pos_pin`, not `limit_neg_pin`. X and Y home
negative and use `limit_neg_pin`.

### Axes homed the wrong way

`positive_direction: false` for X and Y, `true` for Z, plus `:low` on the
direction pins for X, Y1 and Y2. Z's direction pin stayed uninverted.

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

Measured travel from the home switch is **115 mm**, now set as
`max_travel_mm: 115.000`.

That leaves 10 mm of clearance below the Z−105 the tool changer plunges to. It
works, but it is the tightest margin on the machine — see `tool-changer.md`.

## Open

### Magazine pitch — confirm pocket 6

The 45.000 mm pitch has not been checked against a far pocket since the Y
coordinates were re-measured. Pocket 1 is Y85.400, so pocket 6 computes to
Y310.400. Park there and confirm the spindle is centred.

An earlier 0.4 mm discrepancy between pockets 1 and 6 was measured while the Y
rail was still binding, so it is not evidence of a pitch error — but it has not
been re-checked either.
