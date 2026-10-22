#!/usr/bin/env python3
"""Generate a surfacing (spoil board / slab flattening) program.

    python tools/surface.py --length 400 --width 300 --depth 1.5 -o surface.nc

Work coordinates throughout, G54, metric. Set work zero at the corner of the
board nearest the front-left, with Z0 on the surface you are cutting down from.
The board is then +X to the right and +Y toward the back, matching the machine
after the 2026-10-19 axis flip.

The cutter deliberately overhangs every edge so the whole surface is cut, and
plunges off the corner of the board rather than into it.
"""

import argparse
import math
import sys


def passes_across(width, stepover):
    """Pass centre lines from Y=0 to Y=width, evenly spaced, <= stepover apart.

    Centres at 0 and width mean the cutter overhangs both edges by its radius,
    which is what guarantees full coverage.
    """
    if width <= 0:
        return [0.0]
    n = max(1, math.ceil(width / stepover))
    step = width / n
    return [i * step for i in range(n + 1)]


def depth_levels(depth, max_doc):
    """Z levels to cut at, evenly split so no pass exceeds max_doc."""
    if depth <= 0:
        return []
    n = max(1, math.ceil(depth / max_doc))
    step = depth / n
    return [-(i + 1) * step for i in range(n)]


def scallop_height(stepover, tool_dia, corner_radius):
    """Ridge left between adjacent passes, mm. None if the cutter cannot reach.

    The flat part of a cutter with rounded insert corners is tool_dia - 2R
    wide. While the flats of adjacent passes overlap there is no ridge at all.
    Past that the overlap falls on the corner arc, and the peak sits midway
    between the two pass centres.
    """
    if corner_radius <= 0:
        return 0.0
    flat_half = tool_dia / 2.0 - corner_radius
    d = stepover / 2.0 - flat_half          # how far past the flat the peak is
    if d <= 0:
        return 0.0                          # flats overlap, surface is flat
    if d >= corner_radius:
        return None                         # periphery does not reach at all
    return corner_radius - math.sqrt(corner_radius ** 2 - d ** 2)


def problem(a):
    """Return a complaint about the settings, or None if they are workable."""
    for name, val in (("length", a.length), ("width", a.width),
                      ("depth", a.depth), ("tool diameter", a.tool_dia),
                      ("depth of cut", a.doc)):
        if val is None or val <= 0:
            return f"{name} must be greater than zero"
    if not 0 < a.stepover <= 1:
        return "stepover must be between 0 and 1"
    if a.corner_radius < 0 or a.corner_radius * 2 >= a.tool_dia:
        return "corner radius must be less than half the cutter diameter"
    if scallop_height(a.tool_dia * a.stepover, a.tool_dia, a.corner_radius) is None:
        flat = a.tool_dia - 2 * a.corner_radius
        return (f"a {a.tool_dia:g} mm cutter with a {a.corner_radius:g} mm corner radius "
                f"cannot step over {a.tool_dia * a.stepover:.2f} mm - the periphery does "
                f"not reach between passes and material would be left uncut. "
                f"Keep the stepover at or below {flat / a.tool_dia:.2f} "
                f"({flat:.2f} mm)")
    return None


def ask(label, default=None, unit="mm"):
    """Prompt until a usable number comes back. Enter accepts the default."""
    while True:
        shown = f" [{f'{default:g} {unit}'.strip()}]" if default is not None else ""
        try:
            raw = input(f"  {label}{shown}: ").strip()
        except EOFError:
            if default is not None:
                print()
                return default
            sys.exit("\nnothing to read - pass the values as options instead")
        if not raw:
            if default is not None:
                return default
            print("      needed")
            continue
        try:
            return float(raw)
        except ValueError:
            print("      not a number")


def interactive(a):
    print("Surfacing program. Enter accepts the value in brackets.\n")
    while True:
        print(" Board, measured from the front-left corner:")
        a.length = ask("length along X", a.length)
        a.width = ask("width along Y", a.width)
        a.depth = ask("material to remove", a.depth)
        print("\n Cutter:")
        a.tool_dia = ask("diameter", a.tool_dia)
        a.corner_radius = ask("insert corner radius, 0 if square", a.corner_radius)
        print("\n Cutting:")
        a.stepover = ask("stepover as a fraction of diameter", a.stepover, unit="")
        a.doc = ask("max depth per pass", a.doc)
        a.feed = ask("feed", a.feed, unit="mm/min")
        a.rpm = int(ask("spindle speed", a.rpm, unit="rpm"))
        a.safe_z = ask("safe Z above work zero", a.safe_z)

        bad = problem(a)
        if not bad:
            return
        print(f"\n  {bad}\n  Try again.\n")


def lint(lines):
    """Complaints about anything a G-code parser would reject.

    Exists because a nested paren in a comment - "3 depth pass(es)" - shipped
    once and alarmed the controller at line 3. The geometry had been checked
    carefully; that the file parsed at all had not.
    """
    out = []
    for i, line in enumerate(lines, 1):
        depth = 0
        for col, ch in enumerate(line):
            if ch == "(":
                depth += 1
                if depth > 1:
                    out.append(f"line {i} col {col + 1}: '(' inside a comment - "
                               f"the parser ends the comment at the first ')': {line}")
            elif ch == ")":
                depth -= 1
                if depth < 0:
                    out.append(f"line {i} col {col + 1}: ')' with no open comment: {line}")
                    depth = 0
        if depth:
            out.append(f"line {i}: comment never closed: {line}")
        if ";" in line:
            out.append(f"line {i}: ';' is not a comment in this dialect: {line}")
    return out


def generate(a):
    r = a.tool_dia / 2.0
    x_start = -r - a.lead
    x_end = a.length + r + a.lead
    y_lines = passes_across(a.width, a.tool_dia * a.stepover)
    z_levels = depth_levels(a.depth, a.doc)

    if not z_levels:
        sys.exit("--depth must be greater than zero")

    g = []
    e = g.append
    e(f"(Surfacing {a.length} x {a.width} mm, removing {a.depth} mm)")
    e(f"(Tool {a.tool_dia} mm, stepover {a.stepover * 100:.0f}% = "
      f"{a.tool_dia * a.stepover:.2f} mm)")
    e(f"({len(z_levels)} depth {'pass' if len(z_levels) == 1 else 'passes'}, "
      f"{len(y_lines)} lines each)")
    e("(Work coordinates. Zero at the front-left corner, Z0 on the surface.)")
    e(f"(Cutter centre spans X {x_start:.3f} to {x_end:.3f}, "
      f"Y {y_lines[0]:.3f} to {y_lines[-1]:.3f})")
    e("")
    e("G21 G90 G54")
    e("G17")
    e(f"G0 Z{a.safe_z:.3f}")
    e(f"M3 S{a.rpm}")
    e("G4 P2")
    e("")

    cut_distance = 0.0
    for zi, z in enumerate(z_levels, 1):
        e(f"(--- depth pass {zi} of {len(z_levels)}: Z{z:.3f} ---)")
        e(f"G0 Z{a.safe_z:.3f}")
        e(f"G0 X{x_start:.3f} Y{y_lines[0]:.3f}")
        e(f"G1 Z{z:.3f} F{a.plunge_feed:.1f}")

        at_start = True
        for li, y in enumerate(y_lines):
            if li:                      # step over at depth, cutting as it goes
                e(f"G1 Y{y:.3f} F{a.feed:.1f}")
                cut_distance += abs(y - y_lines[li - 1])
            x = x_end if at_start else x_start
            e(f"G1 X{x:.3f} F{a.feed:.1f}")
            cut_distance += x_end - x_start
            at_start = not at_start
        e("")

    e(f"G0 Z{a.safe_z:.3f}")
    e("M5")
    if a.park:
        e("(park)")
        e(f"G53 G90 G0 X{a.park[0]:.3f} Y{a.park[1]:.3f}")
    e("M30")

    bad = lint(g)
    if bad:
        raise AssertionError(
            "generated G-code would not parse:\n  " + "\n  ".join(bad))

    minutes = cut_distance / a.feed if a.feed else 0
    return "\n".join(g) + "\n", {
        "lines": len(y_lines),
        "depth_passes": len(z_levels),
        "doc_each": a.depth / len(z_levels),
        "cut_distance_m": cut_distance / 1000.0,
        "minutes": minutes,
        "x_span": (x_start, x_end),
        "y_span": (y_lines[0], y_lines[-1]),
        "z_min": z_levels[-1],
    }


def main():
    p = argparse.ArgumentParser(description="Generate a surfacing program (metric, work coordinates)")
    p.add_argument("--length", type=float, help="board size along X, mm")
    p.add_argument("--width", type=float, help="board size along Y, mm")
    p.add_argument("--depth", type=float, help="total material to remove, mm")
    p.add_argument("--tool-dia", type=float, default=25.4, help="cutter diameter, mm (default 25.4)")
    p.add_argument("--stepover", type=float, default=0.4,
                   help="fraction of cutter diameter, 0-1 (default 0.4)")
    p.add_argument("--corner-radius", type=float, default=0.0,
                   help="insert corner radius, mm. The flat part of the cut is "
                        "tool-dia minus twice this, which is what limits stepover")
    p.add_argument("--doc", type=float, default=0.5, help="max depth per pass, mm (default 0.5)")
    p.add_argument("--feed", type=float, default=2000.0, help="cutting feed, mm/min")
    p.add_argument("--plunge-feed", type=float, default=300.0, help="plunge feed, mm/min")
    p.add_argument("--rpm", type=int, default=15000, help="spindle speed")
    p.add_argument("--safe-z", type=float, default=5.0, help="retract height above work zero, mm")
    p.add_argument("--lead", type=float, default=2.0, help="extra run-off past each end, mm")
    p.add_argument("--park", type=float, nargs=2, metavar=("X", "Y"),
                   help="machine coordinates to park at when finished (G53)")
    p.add_argument("-o", "--out", help="write here instead of stdout")
    p.add_argument("--ask", action="store_true",
                   help="prompt for the values instead of taking them as options "
                        "(the default when run with no options at all)")
    a = p.parse_args()

    asking = a.ask or (a.length is None and a.width is None and a.depth is None)
    if asking:
        interactive(a)
        if not a.out:
            try:
                name = input("\n  write to [surface.nc]: ").strip()
            except EOFError:
                name = ""
            a.out = name or "surface.nc"

    if not asking:
        missing = [n for n, v in (("--length", a.length), ("--width", a.width),
                                  ("--depth", a.depth)) if v is None]
        if missing:
            sys.exit(f"missing {', '.join(missing)} - supply them, or run with no "
                     f"options at all to be asked")
    bad = problem(a)
    if bad:
        sys.exit(bad)
    ridge = scallop_height(a.tool_dia * a.stepover, a.tool_dia, a.corner_radius)

    text, s = generate(a)

    if a.out:
        with open(a.out, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        print(f"Wrote {a.out}", file=sys.stderr)
    else:
        print(text, end="")

    if ridge:
        flat = a.tool_dia - 2 * a.corner_radius
        ridge_note = (f"  ridge between passes: {ridge * 1000:.0f} microns "
                      f"(stepover is past the {flat:.2f} mm flat)\n")
    elif a.corner_radius:
        ridge_note = "  flats overlap - no ridge between passes\n"
    else:
        ridge_note = ""

    print(
        f"\n  {s['depth_passes']} depth pass(es) at {s['doc_each']:.3f} mm each, "
        f"down to Z{s['z_min']:.3f}\n"
        f"  {s['lines']} lines per pass\n"
        f"  cutter centre X {s['x_span'][0]:.1f} to {s['x_span'][1]:.1f}, "
        f"Y {s['y_span'][0]:.1f} to {s['y_span'][1]:.1f}\n"
        f"  {s['cut_distance_m']:.1f} m of cutting, about {s['minutes']:.0f} min at F{a.feed:.0f}\n"
        + ridge_note
        + f"\n  Work zero must sit so that span fits the machine: "
          f"X -1220..0, Y -1200..0, Z -115..0.",
        file=sys.stderr)


if __name__ == "__main__":
    main()
