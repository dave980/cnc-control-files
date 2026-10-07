# Wiring and pin assignments

## Doberman input pins — the thing to know first

GPIO 36–42 are **opto-isolated inputs with onboard pull-ups**. Consequences:

- Never add `:pu` or `:pd` — the pull-up is already on the board
- NPN-NO sensors use `:low`
- These pins **cannot be used as outputs**. The GPIO sits behind a phototransistor
  and can only read. Configuring one as an output throws no error and does nothing.
- A `Switch Vcc` jumper selects 5 V or Vin (12 V) for *all* inputs together
- The PCB LED lights when an input is pulled low

This board is set to **5 V**, because the tool changer's sensors need 5 V.

## Endstops

ROURCK SN04-N inductive, NPN-NO, running at 12 V from the main supply.
Brown to +12 V, blue to 0 V, black to the input pin.

| Axis | Pin | Config |
|---|---|---|
| X | gpio.42 | `limit_neg_pin: gpio.42:low` |
| Y1 | gpio.41 | `limit_neg_pin: gpio.41:low` |
| Y2 | gpio.40 | `limit_neg_pin: gpio.40:low` |
| Z | gpio.39 | `limit_pos_pin: gpio.39:low` — Z homes up |

X and Y home negative, Z homes positive. All three home to `mpos_mm: 0`, so after
`$H` the machine reads 0, 0, 0 and machine zero sits at the switches.

## Spindle — 0-10 V module

| Signal | Pin |
|---|---|
| Analog out | gpio.6 |
| Forward | gpio.7 |
| Reverse | gpio.8 |

The Doberman 0-10 V module labels its terminals **VI** (signal), **Grn** (analog
common), **Out1** (= FWD), **Out2** (= REV) and **Com** (digital common) rather
than the generic names. The YL620-A has no terminal marked plain `COM` — digital
common is **XGND** and analog common is a separate **GND**.

The module's trim pot is set to 10.13 V measured under load, which gives 392 Hz at
a commanded S24000.

## Tool changer — 5-wire harness

| Wire | Function | Pin |
|---|---|---|
| Red | 5 V | input header Vcc |
| Black | Ground | input header GND |
| Green | Tool setter | gpio.36, `probe: pin: gpio.36:low` |
| Yellow | IR beam | gpio.38, `user_inputs: digital0_pin: gpio.38:low` |
| Blue | Dust cover | see below — not currently connected |

IR beam reads **1 when clear, 0 when blocked**, verified on the machine.
The macros read it with `M66 P0 L0` into `#5399`.

## Doberman outputs, for reference

Four 5 V outputs on red 2-pin connectors, driven by a 74AHCT125 — true push-pull
5 V, 20 mA each and 50 mA total. Left to right:

| Position | Pin | Note |
|---|---|---|
| 1st | gpio.4 | also fires MOSFET1 |
| 2nd | gpio.5 | also fires MOSFET2 |
| 3rd | gpio.46 | ESP32-S3 strapping pin |
| 4th | gpio.45 | ESP32-S3 strapping pin |

On each connector, **pin 2 is signal and pin 1 is ground**.

Two MOSFETs, 3 A continuous / 5 A peak, with flyback diodes to VMot. They switch
to ground when their GPIO is active, and VMot is always 12 V. They share gpio.4
and gpio.5 with the first two 5 V outputs, so driving those outputs fires a MOSFET
as a side effect — avoid them for logic signals if anything is attached.
