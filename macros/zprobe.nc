(Z zero on the work with the V1 Engineering touch plate on gpio.48)
(Order: M6 T<n> first so the tool is measured on the setter, THEN this.)
(Put the plate on the work under the bit, clip the lead to the bit or collet nut.)
(Plate thickness measured 0.5 mm - change #<_zp_plate> if the plate changes.)
M5
o1000 if [#<_metric> EQ 0]
    #<_zp_return_units> = 20
o1000 else
    #<_zp_return_units> = 21
o1000 endif
#<_zp_plate> = 0.5
G21 G91
G38.2 Z-25.000 F150.0
G38.4 Z3.000 F25.0
G10 L20 P0 Z[#<_zp_plate>]
G0 Z5.000
G90
G[#<_zp_return_units>]
(print, Z zero set on the work surface. Remove the plate and clip.)
