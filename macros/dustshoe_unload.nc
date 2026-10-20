(dustshoe_unload.nc -- park the magnetic dust shoe in its stand)
(All moves are G53 machine coordinates. Machine Z0 is the ceiling.)
(Positions match the dust shoe block in tc.nc -- change both together.)

#<ds_park_x>   = 1210.000     (XY where the shoe sits fully home in the stand)
#<ds_park_y>   = -610.000
#<ds_clear_x>  = 1210.000     (XY in line with the stand rails, shoe fully clear of them)
#<ds_clear_y>  = -730.000
#<ds_engage_z> = -87.500     (Z where the shoe's side slot lines up with the stand flanges)
#<ds_lift>     = 15.000    (how far to pull straight up to break the magnets)
#<ds_slide_f>  = 1000.0    (feed for sliding into the stand)
#<ds_lift_f>   = 300.0     (feed for pulling off the magnets)

o100 if [#<ds_park_x> EQ 0]
    (print, Dust shoe positions not set in dustshoe_unload.nc. Aborted.)
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

(Up to the ceiling, then over to the lead-in point outside the stand)
G53 G90 G0 Z0.000
G53 G90 G0 X[#<ds_clear_x>] Y[#<ds_clear_y>]
G53 G90 G0 Z[#<ds_engage_z>]

(Slide the shoe's slot onto the stand flanges)
G53 G90 G1 X[#<ds_park_x>] Y[#<ds_park_y>] F[#<ds_slide_f>]

(Pull straight up -- the flanges hold the shoe, the magnets let go)
G53 G90 G1 Z[#<ds_engage_z> + #<ds_lift>] F[#<ds_lift_f>]
G53 G90 G0 Z0.000

(Back to where we started, at the ceiling)
G53 G90 G0 X[#<ds_start_x>] Y[#<ds_start_y>]
(print, Dust shoe parked.)
G[#<ds_units>]
