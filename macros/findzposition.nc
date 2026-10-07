M5
o1000 if [#<_metric> EQ 0]
    #<_rc_return_units> = 20
o1000 else
    #<_rc_return_units> = 21
o1000 endif
G21 G90
G4 P0.1
M66 P0 L0
o2000 if [#5399 EQ 1]
    (print, Beam reads clear. Check beam state.)
    $Alarm/Send=3
o2000 endif
o3000 while [#5399 EQ 0]
    G91 G1 Z0.100 F250.0
    G4 P0.1
    M66 P0 L0
o3000 endwhile
G90
G[#<_rc_return_units>]
(print, Z Position: #<_rc_z_pos>)
