#!/usr/bin/env python3
"""
Read every parameter out of a YL620-A VFD over Modbus RTU and write them to a
file.

READ ONLY. This never issues a write function code, so it cannot change the
drive's configuration. Nothing here will alter your setup.

    pip install pyserial
    python tools/vfd_dump.py --port COM5 -o docs/vfd-parameters.md
    python tools/vfd_dump.py --port /dev/ttyUSB0

Needs a USB-to-RS485 adapter on the VFD's 485 terminals. Mind A/B polarity; if
every read times out, swap them.

Comms defaults below match this machine: P03.00=4 (19200), P03.01=10 (address),
P03.02=2 (8N1).

Register mapping: Pgg.ii lives at register (gg * 256 + ii), so P03.12 is
0x030C. Confirmed against FluidNC's own YL620 driver, which reads 0x0308/0x0309
and treats them as P03.08/P03.09.
"""

import argparse
import sys
import time

# Parameter groups and how far each one runs. Generous upper bounds - reads of
# addresses the drive does not implement just return an exception and are
# skipped.
GROUPS = {
    0: 26, 1: 22, 2: 11, 3: 20, 4: 12, 5: 13, 6: 19,
    7: 18, 8: 11, 9: 4, 10: 4, 11: 5, 12: 21, 13: 6,
}


def crc16(data: bytes) -> bytes:
    crc = 0xFFFF
    for byte in data:
        crc ^= byte
        for _ in range(8):
            if crc & 1:
                crc = (crc >> 1) ^ 0xA001
            else:
                crc >>= 1
    return bytes([crc & 0xFF, (crc >> 8) & 0xFF])


def read_register(port, slave, reg, retries=2):
    """Modbus function 03. Returns the value, or None."""
    frame = bytes([slave, 0x03, reg >> 8, reg & 0xFF, 0x00, 0x01])
    frame += crc16(frame)

    for _ in range(retries):
        port.reset_input_buffer()
        port.write(frame)
        reply = port.read(7)

        if len(reply) == 7 and reply[0] == slave and reply[1] == 0x03:
            if crc16(reply[:5]) == reply[5:7]:
                return (reply[3] << 8) | reply[4]
        # an exception reply (0x83) means the register does not exist - normal
        if len(reply) >= 2 and reply[1] == 0x83:
            return None
        time.sleep(0.05)
    return None


def main():
    ap = argparse.ArgumentParser(description="Dump YL620-A parameters (read only)")
    ap.add_argument("--port", help="serial port, e.g. COM5 or /dev/ttyUSB0")
    ap.add_argument("--list", action="store_true",
                    help="list the serial ports this machine can actually see, then exit")
    ap.add_argument("--baud", type=int, default=19200, help="default 19200 (P03.00=4)")
    ap.add_argument("--slave", type=int, default=10, help="default 10 (P03.01)")
    ap.add_argument("-o", "--out", help="write markdown here instead of stdout")
    args = ap.parse_args()

    try:
        import serial
    except ImportError:
        sys.exit("pyserial missing:  pip install pyserial")

    if args.list:
        from serial.tools import list_ports
        found = list(list_ports.comports())
        if not found:
            sys.exit("No serial ports visible at all. The adapter is not enumerating — "
                     "check the USB cable and that the driver installed.")
        for p in found:
            vid_pid = f"{p.vid:04X}:{p.pid:04X}" if p.vid is not None else "  no USB id  "
            print(f"{p.device:<8} {vid_pid}  {p.description}")
        print("\nAn FTDI adapter shows VID 0403. A port with no USB id is "
              "on-board or a leftover entry, not your adapter.")
        return

    if not args.port:
        sys.exit("--port is required (or use --list to see what is available)")

    try:
        port = serial.Serial(args.port, args.baud, bytesize=8,
                             parity=serial.PARITY_NONE, stopbits=1, timeout=0.3)
    except (serial.SerialException, OSError) as e:
        hint = ""
        if "semaphore" in str(e).lower() or getattr(e, "winerror", None) == 121:
            hint = ("\n\nWindows error 121 means the port was found in the registry but the "
                    "device behind it did not answer. It is a host/adapter problem — nothing "
                    "has been sent to the VFD yet, so wiring, baud and A/B polarity are not "
                    "involved.\n"
                    "  - run with --list to see which ports really exist right now\n"
                    "  - unplug and replug the adapter and watch whether the port appears\n"
                    "  - try a different USB port, directly on the PC, not through a hub\n"
                    "  - COM5 may be a leftover entry from a previous adapter")
        sys.exit(f"cannot open {args.port}: {e}{hint}")

    rows, missing = [], 0
    with port:
        time.sleep(0.2)
        for group, count in sorted(GROUPS.items()):
            for index in range(count):
                reg = group * 256 + index
                value = read_register(port, args.slave, reg)
                if value is None:
                    missing += 1
                    continue
                rows.append((f"P{group:02d}.{index:02d}", reg, value))
                print(f"  P{group:02d}.{index:02d}  0x{reg:04X}  {value}", file=sys.stderr)

    if not rows:
        sys.exit("No parameters read. Check A/B polarity, the port, baud "
                 f"({args.baud}) and the slave address ({args.slave}).")

    out = [
        "# YL620-A parameters, as read from the drive",
        "",
        f"Read over Modbus RTU at {args.baud} 8N1, slave {args.slave}, "
        f"by `tools/vfd_dump.py`. {len(rows)} parameters; {missing} addresses "
        "did not respond, which is expected for unimplemented ones.",
        "",
        "**Values are raw register contents.** Most frequencies are stored in "
        "0.1 Hz, so 4000 means 400.0 Hz and 300 means 30.0 Hz — the same "
        "convention as the front panel display. Percentages and times scale "
        "similarly. Check `docs/vfd-yl620a.md` for the ones that matter here.",
        "",
        "| Parameter | Register | Raw value |",
        "|---|---|---|",
    ]
    out += [f"| {name} | 0x{reg:04X} | {value} |" for name, reg, value in rows]
    text = "\n".join(out) + "\n"

    if args.out:
        with open(args.out, "w") as f:
            f.write(text)
        print(f"\nWrote {len(rows)} parameters to {args.out}", file=sys.stderr)
    else:
        print(text)


if __name__ == "__main__":
    main()
