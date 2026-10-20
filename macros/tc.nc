o1000 if [#<_current_tool> LT 0]
    (print, Current tool not initialized. Tool change aborted.)
    $Alarm/Send=3
o1000 elseif [#<_selected_tool> EQ #<_current_tool>]
    (print, Current tool selected. Tool change bypassed.)
o1000 else
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
    G4 P0.1
    M66 P0 L0
    o1200 if [#5399 EQ 0]
        (print, IR beam obstructed.)
        $Alarm/Send=3
    o1200 endif
    (--- Dust shoe off: slide onto the stand at X1210 Y-610, lift off the magnets ---)
    (Positions match macros/dustshoe_unload.nc -- change both together)
    G53 G90 G0 Z0.000
    G53 G90 G0 X1210.000 Y-730.000
    G53 G90 G0 Z-87.500
    G53 G90 G1 Y-610.000 F1000.0
    G53 G90 G1 Z-72.500 F300.0
    G53 G90 G0 Z0.000
    G53 G90 G0 Z0.000
    G43.1 Z0
    G4 P0.1
    #<z_offset> = [0.000 - #<_z>]
    o1300 if [#<_current_tool> EQ 0]
    o1300 elseif [#<_current_tool> GT 6]
        G53 G90 G0 Z0.000
        G53 G90 G0 X1100.000 Y-32.000
        (print, Tool is out of range. Manually unload tool and cycle start to continue.)
        M0
    o1300 else
        G53 G90 G0 X1211.400 Y[-85.400 - [[#<_current_tool> - 1] * 45.000]]
        G53 G90 G0 Z-82.000
        M4 S2100.0
        G4 P1
        G53 G90 G1 Z-105.000 F2000.0
        G53 G90 G1 Z-93.000 F2000.0
        G53 G90 G0 Z-74.000
        G4 P0.1
        M66 P0 L0
        o1310 if [#5399 EQ 0]
            G53 G90 G0 Z-82.000
            G53 G90 G1 Z-105.000 F2000.0
            G53 G90 G1 Z-93.000 F2000.0
            M5
            G53 G90 G0 Z-74.000
            o1311 if [#5399 EQ 0]
                G53 G90 G0 Z0.000
                (print, Failed unload at zone 1. Manually unload tool and cycle start to continue.)
                M0
            o1311 else
                G53 G90 G0 Z0.000
            o1311 endif
        o1310 else
            M5
            G53 G90 G0 Z0.000
        o1310 endif
    o1300 endif
    o1400 if [#<_selected_tool> EQ 0]
        G53 G90 G0 Z0.000
    o1400 elseif [#<_selected_tool> LE 6]
        G53 G90 G0 X1211.400 Y[-85.400 - [[#<_selected_tool> - 1] * 45.000]]
        G53 G90 G0 Z-82.000
        M3 S1800.0
        G4 P1
        G53 G90 G1 Z-105.000 F2000.0
        G53 G90 G1 Z-93.000 F2000.0
        G53 G90 G1 Z-105.000 F2000.0
        G53 G90 G1 Z-93.000 F2000.0
        M5
        G53 G90 G0 Z-74.000
        G4 P0.1
        M66 P0 L0
        o1410 if [#5399 EQ 1]
            G53 G90 G0 Z0.000
            (print, Failed load at zone 1. Manually load tool and cycle start to continue.)
            M0
        o1410 else
            G53 G90 G0 Z-68.000
            G4 P0.1
            M66 P0 L0
            o1411 if [#5399 EQ 0]
                G53 G90 G0 Z0.000
                (print, Failed load at zone 2. Manually load tool and cycle start to continue.)
                M0
            o1411 else
                G53 G90 G0 Z0.000
            o1411 endif
        o1410 endif
    o1400 else
        G53 G90 G0 Z0.000
        G53 G90 G0 X1100.000 Y-32.000
        (print, Tool is out of range. Manually load tool and cycle start to continue.)
        M0
    o1400 endif
    M61 Q[#<_selected_tool>]
    o1500 if [#<_selected_tool> GT 0]
        G53 G90 G0 X1211.000 Y-32.000
        G53 G90 G0 Z0.000
        G38.2 G91 Z-75.000 F600.0
        G38.4 G91 Z10.000 F50.0
        G43.1 Z[#5063]
    o1500 endif
    G53 G90 G0 Z0.000
    (--- Dust shoe back on: drop onto it at X1210 Y-610, slide out to Y-730 ---)
    (Positions match macros/dustshoe_load.nc -- change both together)
    G53 G90 G0 X1210.000 Y-610.000
    G53 G90 G0 Z-72.500
    G53 G90 G1 Z-87.500 F300.0
    G4 P0.3
    G53 G90 G1 Y-730.000 F1000.0
    G53 G90 G0 Z0.000
    G53 G90 G0 X[#<_rc_start_x>] Y[#<_rc_start_y>]
    G4 P0
    G[#<_rc_return_units>]
o1000 endif
