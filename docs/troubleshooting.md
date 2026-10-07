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
- Sensors were on 5 V and marginal. Moved to 12 V from the main supply.
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

## Open

### Dust cover

See `tool-changer.md`. Removed from the config; the signal spec is undocumented
and 5 V logic does not drive it. RapidChange's Discord is the place to resolve it.

### Y drifts slightly, unequally between sides

Both sides of the gantry drift over repeated moves, by different amounts.

Ruled out so far:

- Y/Y2 auto-squaring works — the homing log shows Y2 tripping ~0.018 mm before Y,
  so the gantry is square **at home**. Any racking happens during motion.
- The stepping engine name parses correctly (FluidNC matches enums
  case-insensitively, so `I2S_STream` is fine).
- Acceleration is gentle — 150 mm/s² with a 3000 mm/min rapid is 0.33 s and 8 mm
  to reach full speed.

Still to check:

- **The CL57T drivers are closed loop.** They correct position error rather than
  losing steps silently, but they fault and assert their ALM output when error
  exceeds their limit. If ALM is not wired to the controller, a fault looks
  exactly like lost steps. This is the first thing to check.
- Hand-feel test with the machine powered down (`idle_ms: 255` keeps motors
  energised, so the controller must be off). Uniform stiffness points at
  lubrication; tight spots point at rail alignment.
- HGR rails have almost no compliance. Two rails out of parallel by 0.1 mm over
  1180 mm will bind, and the tighter side loses more — which matches the symptom.
  Check centre-to-centre at several points, or loosen one rail and let the gantry
  set the parallelism as you torque from one end.
- Grease the four HGR carriages — lithium NLGI 2, a few pumps each through the
  end-cap zerk, then cycle the travel and wipe.

### Magazine pitch

Pocket 1 measured at Y80.6 and pocket 6 was reported at Y306. With a 45.000 mm
pitch, pocket 6 computes to 305.6. If pocket 6 really wants 306, the pitch is
45.08 rather than 45.000. Worth settling, because a pitch error and the Y drift
produce the same symptom at the far pockets.
