# Versal Prime `xcvm1102-sfva784-2MP-e-S`. Only `led` is external —
# clock and reset are driven internally by the CIPS `pl0_ref_clk` /
# `pl0_resetn` outputs (see `blink_bd.tcl`). `E14` is an HD I/O
# reachable on the SFVA784 package.

set_property -dict {PACKAGE_PIN E14 IOSTANDARD LVCMOS18} [get_ports led]
