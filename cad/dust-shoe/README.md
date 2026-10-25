# Dust shoe

Dust removal system for the mill, designed in Autodesk Fusion.

| File | What |
|---|---|
| `cnc-dust-shoe.f3d` | Fusion archive — in Fusion, File → Open → Open from my computer |
| `stl/*.stl` | One binary STL per dust shoe body, in millimetres |
| `stl/*.3mf` | Printable 3MF models — the dust extraction fittings below |

The STL names match the body names in the Fusion browser.

| Part | File | Size (mm) |
|---|---|---|
| Top Shoe | `top-shoe.stl` | 230.0 x 110.4 x 60.0 |
| Bottom Shoe | `bottom-shoe.stl` | 230.0 x 110.4 x 30.0 |
| Shoe Brush | `shoe-brush.stl` | 300.0 x 33.0 x 4.8 |
| Shoe Dock | `shoe-dock.stl` | 65.0 x 120.0 x 73.5 |
| Hose Holder Front | `hose-holder-front.stl` | 235.7 x 117.5 x 25.0 |
| Hose Holder Rear | `hose-holder-rear.stl` | 228.1 x 116.0 x 25.0 |
| Spindle Holder 1 | `spindle-holder-1.stl` | 158.0 x 37.5 x 108.0 |
| Spindle Holder 2 | `spindle-holder-2.stl` | 158.0 x 37.5 x 108.0 |

Sizes are bounding boxes measured from the STL geometry, in the design's
orientation rather than print orientation.

The parts were called `body3`, `body8` and so on until 2026-10-22. The
geometry did not change when they were renamed — every file is byte-identical
to the one it replaced:

| Part | Was |
|---|---|
| Top Shoe | body3 |
| Spindle Holder 1 | body8 |
| Spindle Holder 2 | body9 |
| Hose Holder Rear | body14 |
| Hose Holder Front | body15 |
| Shoe Dock | body21 |
| Bottom Shoe | body27 |
| Shoe Brush | body34 |

The Shoe Dock is the parking stand the shoe is left on during a tool change;
`docs/` has its machine coordinates.

## Dust extraction fittings

Separate from the shoe itself — hoses, cuffs and adapters around the shop.
3MF rather than STL, so they carry their own print settings.

| File | What |
|---|---|
| `2in-cuff.3mf` | 2 inch hose cuff |
| `2in-to-4in-adapter.3mf` | 2 to 4 inch step |
| `4in-coupler.3mf` | 4 inch coupler |
| `ryobi-cuff.3mf` | cuff for the Ryobi port |
| `ryobi-mitre-saw-hose-adapter.3mf` | mitre saw dust port adapter — not CNC |
| `solid-brush.3mf` | solid brush |
| `body36.3mf` | unidentified; a Fusion body number rather than a name, and only 1.7 KB |

These sit in `stl/` with the shoe bodies for now. They are a different thing
from the shoe and could reasonably move to their own folder; the mitre saw
adapter in particular has nothing to do with the mill.
