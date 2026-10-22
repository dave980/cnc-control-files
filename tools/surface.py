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
    e(f"({len(z_levels)} depth pass(es), {len(y_lines)} lines each)")
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
        e(f"(park) G53 G90 G0 X{a.park[0]:.3f} Y{a.park[1]:.3f}")
    e("M30")

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
    p.add_argument("--length", type=float, required=True, help="board size along X, mm")
    p.add_argument("--width", type=float, required=True, help="board size along Y, mm")
    p.add_argument("--depth", type=float, required=True, help="total material to remove, mm")
    p.add_argument("--tool-dia", type=float, default=25.4, help="cutter diameter, mm (default 25.4)")
    p.add_argument("--stepover", type=float, default=0.4,
                   help="fraction of cutter diameter, 0-1 (default 0.4)")
    p.add_argument("--doc", type=float, default=0.5, help="max depth per pass, mm (default 0.5)")
    p.add_argument("--feed", type=float, default=2000.0, help="cutting feed, mm/min")
    p.add_argument("--plunge-feed", type=float, default=300.0, help="plunge feed, mm/min")
    p.add_argument("--rpm", type=int, default=15000, help="spindle speed")
    p.add_argument("--safe-z", type=float, default=5.0, help="retract height above work zero, mm")
    p.add_argument("--lead", type=float, default=2.0, help="extra run-off past each end, mm")
    p.add_argument("--park", type=float, nargs=2, metavar=("X", "Y"),
                   help="machine coordinates to park at when finished (G53)")
    p.add_argument("-o", "--out", help="write here instead of stdout")
    a = p.parse_args()

    for name, val in (("length", a.length), ("width", a.width), ("tool-dia", a.tool_dia)):
        if val <= 0:
            sys.exit(f"--{name} must be greater than zero")
    if not 0 < a.stepover <= 1:
        sys.exit("--stepover must be between 0 and 1")
    if a.doc <= 0:
        sys.exit("--doc must be greater than zero")

    text, s = generate(a)

    if a.out:
        with open(a.out, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        print(f"Wrote {a.out}", file=sys.stderr)
    else:
        print(text, end="")

    print(
        f"\n  {s['depth_passes']} depth pass(es) at {s['doc_each']:.3f} mm each, "
        f"down to Z{s['z_min']:.3f}\n"
        f"  {s['lines']} lines per pass\n"
        f"  cutter centre X {s['x_span'][0]:.1f} to {s['x_span'][1]:.1f}, "
        f"Y {s['y_span'][0]:.1f} to {s['y_span'][1]:.1f}\n"
        f"  {s['cut_distance_m']:.1f} m of cutting, about {s['minutes']:.0f} min at F{a.feed:.0f}\n"
        f"\n  Work zero must sit so that span fits the machine: "
        f"X -1220..0, Y -1200..0, Z -115..0.",
        file=sys.stderr)


if __name__ == "__main__":
    main()
