# Digilent Arty A7-35T pin constraints for the `hello` LED blink demo.
# Pins mirror the reference `Arty-A7-35-Master.xdc`
# (github.com/Digilent/digilent-xdc). Speed grade -1L -> LVCMOS33.

# 100 MHz on-board oscillator (E3, LVCMOS33) — drives the reg toggle.
set_property -dict {PACKAGE_PIN E3 IOSTANDARD LVCMOS33} [get_ports clk]
create_clock -name sys_clk -period 10.000 [get_ports clk]

# BTN0 (D9) -> active-high reset.
set_property -dict {PACKAGE_PIN D9 IOSTANDARD LVCMOS33} [get_ports rst]

# LD4 (H5) -> the blinking LED.
set_property -dict {PACKAGE_PIN H5 IOSTANDARD LVCMOS33} [get_ports led]
