# YL620-A VFD — parameters and calibration

Spindle: HLTNC GDZ80X73-2-2, 2.2 kW, **air cooled**, 24000 rpm at 400 Hz.
So 60 rpm per Hz, and the VFD display is in 0.1 Hz units (483 means 48.3 Hz).

## Control

| Parameter | Value | Meaning |
|---|---|---|
| P00.01 | 1 | External terminal control |
| P00.04 | 400.0 | Max output frequency |

## V/F curve — the low-speed fix

Out of the box the spindle would not turn below about S4000. It needs voltage
boost at low frequency to make any torque down there. These came from the
YL620-A setup table's 400 Hz column and they are what made tool-change speeds
possible:

| Parameter | Value | Meaning |
|---|---|---|
| P00.05 | 400 | Max voltage output frequency |
| P00.06 | 100 % | Max output voltage |
| P00.07 | 3.5 Hz | Middle frequency |
| P00.08 | 20 % | Middle voltage |
| P00.09 | 0.2 Hz | Min frequency |
| P00.10 | 10 % | Min voltage |

20 % voltage at 3.5 Hz against the ~0.9 % a straight line would give is the whole
trick.

**Heat warning.** That much boost pushes real current through the windings at low
rpm, and the cooling fan is on the rotor, so there is almost no airflow down there.
Two or three seconds of nut threading during a tool change is fine. Do not leave
the spindle running slowly for minutes, and do not cut at these speeds.

## Analog input scaling

| Parameter | Value | Meaning |
|---|---|---|
| P03.10 | 3 | AI1 A/D lower limit |
| P03.11 | 1010 | AI1 A/D upper limit |
| P03.12 | **0** | Frequency at lower limit |
| P03.13 | 400 | Frequency at upper limit |

**P03.12 must be 0.** The setup table's 400 Hz column sets it to 60, which puts a
60 Hz floor under every commanded speed — those spindles are not normally run
slowly. With a floor, S1800 came out around 48 Hz instead of 30. Zeroing it makes
the curve run 0 → 400 Hz across the full analog range.

## Calibrated result

Measured after P03.12 was zeroed:

| Commanded | VFD display | Actual | Error |
|---|---|---|---|
| S1800 | 305 | ~1,830 rpm | +1.7 % |
| S2100 | 355 | ~2,130 rpm | +1.4 % |
| S24000 | 3920 | ~23,520 rpm | −2.0 % |

Close enough to stop. The residual ~1.2 Hz offset at the bottom and the ~2 %
shortfall at the top are AI1 ADC tolerance. Nut threading depends on the ratio
between spindle rpm and Z feed, and 1.7 % does not move that.

## Other

| Parameter | Value | Note |
|---|---|---|
| P04.09 | 1 s | Stall detection time. Raise to 3 if the VFD faults while threading a nut |
| P06.01 | 9 s | Accel time, 0 to max. From 0 to 30 Hz is only ~0.7 s, so the macro's `G4 P1` dwell is enough |
| P06.02 | 8.6 s | Decel time |
| P12.19 | 13 kHz | PWM frequency |

## FluidNC side

```yaml
speed_map: 0=0.000% 24000=100.000%
```

Linear. All the shaping happens in the VFD.

## Reading the parameters back off the drive

`tools/vfd_dump.py` reads every parameter over Modbus RTU and writes them to a
markdown table. **Read only** — it issues nothing but function code 03, so it
cannot alter the drive.

```
pip install pyserial
python tools/vfd_dump.py --port COM5 -o docs/vfd-parameters.md
```

Adapter used here: **DSD TECH SH-U11F** — isolated, FTDI chip, screw terminals.
Isolation matters in this cabinet: a non-isolated adapter would tie the laptop's
USB ground to the VFD's ground reference, next to a 2.2 kW drive switching at
13 kHz.

Two wires to the VFD's RS485 terminals, A to A and B to B. No termination
resistor — the run is about a metre to a single device. If every read times out,
swap A and B; that is the usual first mistake and it does no harm.

About 12 seconds for the full sweep of 192 addresses; unimplemented ones return
a Modbus exception and are skipped.

Comms settings on this drive, which are the script's defaults:

| Parameter | Value | Meaning |
|---|---|---|
| P03.00 | 4 | 19200 bps |
| P03.01 | 10 | Slave address |
| P03.02 | 2 | 8 data bits, 1 stop, no parity |

### The register mapping

**Pgg.ii is at register `gg * 256 + ii`**, so P03.12 is 0x030C and P12.19 is
0x0C13.

That is not from the YL620 manual, which does not document it. It comes from
FluidNC's own YL620 driver, which reads `03 03 08 00 02` — two registers from
0x0308 — and decodes them as the minimum and maximum RPM. 0x0308 and 0x0309 are
P03.08 and P03.09, the panel potentiometer frequency limits. That pins the
scheme down.

The same driver shows the control registers, which is what FluidNC would use if
this spindle were ever moved from the 0-10 V module to RS485:

| Register | Purpose |
|---|---|
| 0x2000 | Run / direction / stop |
| 0x2001 | Frequency setpoint |
| 0x200B | Output frequency readback |

### Values come back raw

Frequencies are stored in 0.1 Hz, the same as the front panel: 4000 is 400.0 Hz,
300 is 30.0 Hz. That is why P03.12 reads 0 rather than 0.0 and why the display
showed 483 for 48.3 Hz during commissioning.

A dump is the as-built state, not a diff. The parameters that actually matter on
this machine are the ones documented above — the V/F curve and the analog
scaling. The rest are factory defaults, and the setup table PDF is the reference
for what those should be.
