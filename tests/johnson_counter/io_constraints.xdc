# Digilent Arty A7-35T pin map. Reference: Digilent's
# Arty-A7-35-Master.xdc (github.com/Digilent/digilent-xdc).

set_property -dict {PACKAGE_PIN E3 IOSTANDARD LVCMOS33} [get_ports clk]
create_clock -name sys_clk -period 10.000 [get_ports clk]

set_property -dict {PACKAGE_PIN D9 IOSTANDARD LVCMOS33} [get_ports reset]
set_property -dict {PACKAGE_PIN A8 IOSTANDARD LVCMOS33} [get_ports direction]

# led[3:0] -> LD4..LD7 (on-board monochrome LEDs).
set_property -dict {PACKAGE_PIN H5 IOSTANDARD LVCMOS33} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN J5 IOSTANDARD LVCMOS33} [get_ports {led[1]}]
set_property -dict {PACKAGE_PIN T9 IOSTANDARD LVCMOS33} [get_ports {led[2]}]
set_property -dict {PACKAGE_PIN T10 IOSTANDARD LVCMOS33} [get_ports {led[3]}]
# led[7:4] -> PMOD JA pins 1-4 (spillover; Arty only has 4 mono LEDs).
set_property -dict {PACKAGE_PIN G13 IOSTANDARD LVCMOS33} [get_ports {led[4]}]
set_property -dict {PACKAGE_PIN B11 IOSTANDARD LVCMOS33} [get_ports {led[5]}]
set_property -dict {PACKAGE_PIN A11 IOSTANDARD LVCMOS33} [get_ports {led[6]}]
set_property -dict {PACKAGE_PIN D12 IOSTANDARD LVCMOS33} [get_ports {led[7]}]
