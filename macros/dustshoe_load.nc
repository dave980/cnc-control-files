(dustshoe_load.nc -- pick the magnetic dust shoe up out of its stand)
(All moves are G53 machine coordinates. Machine Z0 is the ceiling.)
(Positions match dustshoe_unload.nc and the dust shoe block in tc.nc -- change all three together.)

#<ds_park_x>   = 1210.000     (XY where the shoe sits fully home in the stand)
#<ds_park_y>   = 610.000
#<ds_clear_x>  = 1210.000     (XY in line with the stand rails, shoe fully clear of them)
#<ds_clear_y>  = 730.000
#<ds_engage_z> = -87.500     (Z where the spindle plate meets the parked shoe)
#<ds_lift>     = 15.000    (start the slow descent this far above engage Z)
#<ds_slide_f>  = 1000.0    (feed for sliding out of the stand)
#<ds_lift_f>   = 300.0     (feed for the final descent onto the magnets)

o100 if [#<ds_park_x> EQ 0]
    (print, Dust shoe positions not set in dustshoe_load.nc. Aborted.)
    $Alarm/Send=3
o100 endif

M5
o110 if [#<_metric> EQ 0]
    #<ds_units> = 20
o110 else
    #<ds_units> = 21
o110 endif
G21 G90
#<ds_start_x> = #<_abs_x>
#<ds_start_y> = #<_abs_y>

(If the shoe is already on the spindle, the descent drives it into the stand.)
(Nothing can sense the shoe, so a person confirms.)
(print, Check the dust shoe is in the stand and NOT on the spindle. Cycle start to continue.)
M0

(Up to the ceiling, over the parked shoe, quick drop to just above it)
G53 G90 G0 Z0.000
G53 G90 G0 X[#<ds_park_x>] Y[#<ds_park_y>]
G53 G90 G0 Z[#<ds_engage_z> + #<ds_lift>]

(Slow final descent so the magnets seat without a bang)
G53 G90 G1 Z[#<ds_engage_z>] F[#<ds_lift_f>]
G4 P0.3

(Slide the shoe off the stand flanges)
G53 G90 G1 X[#<ds_clear_x>] Y[#<ds_clear_y>] F[#<ds_slide_f>]
G53 G90 G0 Z0.000

(Back to where we started, at the ceiling)
G53 G90 G0 X[#<ds_start_x>] Y[#<ds_start_y>]
(print, Dust shoe loaded.)
G[#<ds_units>]
