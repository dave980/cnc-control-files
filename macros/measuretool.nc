o1000 if [#<_current_tool> GT 0]
    M5
    o1100 if [#<_metric> EQ 0]
        #<_rc_return_units> = 20
    o1100 else
        #<_rc_return_units> = 21
    o1100 endif
    G21 G90
    #<_rc_start_x> = #<_abs_x>
    #<_rc_start_y> = #<_abs_y>
    G4 P0.5
    G53 G90 G0 Z0.000
    G43.1 Z0
    G4 P0.1
    #<z_offset> = [0.000 - #<_z>]
    G53 G90 G0 X1211.000 Y32.000
    G53 G90 G0 Z0.000
    G38.2 G91 Z-75.000 F600.0
    G38.4 G91 Z10.000 F50.0
    G43.1 Z[#5063]
    G53 G90 G0 Z0.000
    G53 G90 G0 X[#<_rc_start_x>] Y[#<_rc_start_y>]
    G4 P0
    G[#<_rc_return_units>]
o1000 else
    (print, No tool loaded. Tool measure aborted.)
o1000 endif
