#!/usr/bin/env python3
"""Write YL620-A parameters over Modbus RTU, one at a time, with read-back.

Deliberately a separate script from vfd_dump.py, which issues nothing but
function code 03 and therefore cannot alter the drive. That property is worth
keeping provable, so the writing lives here.

    python tools/vfd_set.py --port COM3 --set P12.00=80
    python tools/vfd_set.py --port COM3 --restore docs/vfd-parameters.md

Every write is function 06 (single register), followed by a function 03 read
of the same register to confirm the value took. Nothing is written blind.

WHAT THIS WILL NOT WRITE
    P00.13   parameter lock - value 10 means "restore factory defaults"
    P11.xx   live readings (output current, frequency, heatsink temperature)
    P13.xx   drive identity (software/hardware version, serial, hours)
    P10.01   counter current value
    P10.03   timer current value

STOP THE SPINDLE FIRST. This script cannot reliably tell whether the drive is
running - the registers that look like they should say are ambiguous on this
drive, and a guard that might not work is worse than no guard, because it
invites trust it has not earned. You confirm it, not the script.
"""

import argparse
import re
import sys
import time

sys.path.insert(0, __file__.rsplit("/", 1)[0].rsplit("\\", 1)[0])
from vfd_dump import crc16, read_register  # noqa: E402

# Registers this script refuses to touch, and why.
BLOCKED = {
    0x000D: "P00.13 is the parameter lock; value 10 restores factory defaults",
    0x0A01: "P10.01 is a live counter value",
    0x0A03: "P10.03 is a live timer value",
}
BLOCKED_GROUPS = {
    11: "P11.xx are live readings, not settings",
    13: "P13.xx is drive identity, read only",
}

PARAM_RE = re.compile(r"^P(\d{1,2})\.(\d{1,2})$")


def parse_param(name):
    """'P12.00' -> (register, canonical name). Raises ValueError."""
    m = PARAM_RE.match(name.strip().upper())
    if not m:
        raise ValueError(f"not a parameter name: {name!r} (expected e.g. P12.00)")
    group, index = int(m.group(1)), int(m.group(2))
    if group > 13 or index > 255:
        raise ValueError(f"{name}: out of range")
    return group * 256 + index, f"P{group:02d}.{index:02d}"


def blocked_reason(reg):
    if reg in BLOCKED:
        return BLOCKED[reg]
    group = reg >> 8
    if group in BLOCKED_GROUPS:
        return BLOCKED_GROUPS[group]
    return None


def write_register(port, slave, reg, value, retries=2):
    """Modbus function 06. Returns True if the drive echoed the request."""
    frame = bytes([slave, 0x06, reg >> 8, reg & 0xFF, value >> 8, value & 0xFF])
    frame += crc16(frame)

    for _ in range(retries):
        port.reset_input_buffer()
        port.write(frame)
        reply = port.read(8)
        if reply == frame:          # function 06 echoes the request verbatim
            return True
        if len(reply) >= 2 and reply[1] == 0x86:
            raise RuntimeError(f"drive rejected the write to 0x{reg:04X} "
                               f"(exception {reply[2] if len(reply) > 2 else '?'})")
        time.sleep(0.05)
    return False


def apply_one(port, slave, reg, name, value, dry_run):
    """Write one register and verify. Returns True if the drive now holds value."""
    before = read_register(port, slave, reg)
    if before is None:
        print(f"  {name}  cannot read - skipped")
        return False
    if before == value:
        print(f"  {name}  already {value}")
        return True
    if dry_run:
        print(f"  {name}  {before} -> {value}   (dry run, nothing written)")
        return True

    if not write_register(port, slave, reg, value):
        print(f"  {name}  WRITE FAILED, drive still holds {before}")
        return False

    time.sleep(0.05)
    after = read_register(port, slave, reg)
    if after == value:
        print(f"  {name}  {before} -> {after}")
        return True
    print(f"  {name}  VERIFY FAILED: asked for {value}, drive reports {after}")
    return False


def parse_dump(path):
    """Pull {register: value} out of a vfd_dump.py markdown table."""
    rows = {}
    row_re = re.compile(r"^\|\s*(P\d{2}\.\d{2})\s*\|\s*0x([0-9A-Fa-f]{4})\s*\|\s*(-?\d+)\s*\|")
    with open(path, encoding="utf-8") as f:
        for line in f:
            m = row_re.match(line)
            if m:
                rows[int(m.group(2), 16)] = (m.group(1), int(m.group(3)))
    if not rows:
        raise ValueError(f"no parameter rows found in {path}")
    return rows


def main():
    ap = argparse.ArgumentParser(description="Write YL620-A parameters (verified)")
    ap.add_argument("--port", required=True, help="serial port, e.g. COM3")
    ap.add_argument("--baud", type=int, default=19200)
    ap.add_argument("--slave", type=int, default=10)
    ap.add_argument("--set", action="append", metavar="Pgg.ii=VALUE", default=[],
                    help="write one parameter; repeatable")
    ap.add_argument("--restore", metavar="DUMP.md",
                    help="compare the drive against a saved dump and write back "
                         "only the settings that differ")
    ap.add_argument("--dry-run", action="store_true",
                    help="show what would change without writing anything")
    ap.add_argument("--yes", action="store_true",
                    help="skip the confirmation prompt (for scripted use)")
    args = ap.parse_args()

    if not args.set and not args.restore:
        sys.exit("nothing to do: pass --set or --restore")

    try:
        import serial
    except ImportError:
        sys.exit("pyserial missing:  pip install pyserial")

    # Build the work list before opening the port, so bad input costs nothing.
    targets = []  # (reg, name, value)
    for item in args.set:
        if "=" not in item:
            sys.exit(f"--set wants Pgg.ii=VALUE, got {item!r}")
        name, _, raw = item.partition("=")
        try:
            reg, canon = parse_param(name)
            value = int(raw, 0)
        except ValueError as e:
            sys.exit(str(e))
        if not 0 <= value <= 0xFFFF:
            sys.exit(f"{canon}: {value} does not fit in a 16 bit register")
        why = blocked_reason(reg)
        if why:
            sys.exit(f"refusing to write {canon}: {why}")
        targets.append((reg, canon, value))

    try:
        port = serial.Serial(args.port, args.baud, bytesize=8,
                             parity=serial.PARITY_NONE, stopbits=1, timeout=0.3)
    except (serial.SerialException, OSError) as e:
        sys.exit(f"cannot open {args.port}: {e}\n"
                 "Run 'python tools/vfd_dump.py --list' to see the real ports.")

    with port:
        time.sleep(0.2)

        if args.restore:
            try:
                saved = parse_dump(args.restore)
            except (OSError, ValueError) as e:
                sys.exit(str(e))
            print(f"Comparing the drive against {args.restore} ...")
            skipped = 0
            for reg, (canon, value) in sorted(saved.items()):
                if blocked_reason(reg):
                    skipped += 1
                    continue
                live = read_register(port, args.slave, reg)
                if live is not None and live != value:
                    targets.append((reg, canon, value))
            print(f"{len(targets)} differ, {skipped} skipped as unwritable.\n")
            if not targets:
                print("Drive already matches the saved dump. Nothing to do.")
                return

        print("About to write:" if not args.dry_run else "Would write:")
        for reg, canon, value in targets:
            print(f"  {canon}  0x{reg:04X}  <- {value}")

        if not args.dry_run and not args.yes:
            print("\nThe spindle must be STOPPED. This script cannot check that for you.")
            if input("Type 'write' to continue: ").strip().lower() != "write":
                sys.exit("aborted, nothing written")

        print()
        ok = sum(apply_one(port, args.slave, reg, canon, value, args.dry_run)
                 for reg, canon, value in targets)

    print(f"\n{ok}/{len(targets)} confirmed.")
    if ok != len(targets):
        sys.exit("some writes did not take - re-read the drive before trusting it")


if __name__ == "__main__":
    main()
