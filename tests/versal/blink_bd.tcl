# Minimal Versal BD wrapping `blink`. The BD exists for one reason:
# Versal's `place_design` DRC (`CIPS-1`) rejects any design that
# doesn't have a `versal_cips` cell in the netlist hierarchy, so a
# raw RTL-only `blink` can't reach placement on this family.
#
# CIPS drives blink's clock. CIPS in its minimal config only exposes
# `pl0_ref_clk`, no PL reset, so `rst` is tied to 0 via `xlconstant`
# (blink's FFs power up to 0 through GSR on Versal). The only
# exported port is `led`.

create_bd_design "blink_bd"

# --- Versal CIPS: satisfies DRC CIPS-1 and provides PL clock 0.
create_bd_cell -type ip -vlnv xilinx.com:ip:versal_cips:3.4 versal_cips_0
set_property -dict [list \
    CONFIG.CLOCK_MODE {Custom} \
    CONFIG.PS_PMC_CONFIG [list \
        PS_USE_PMCPL_CLK0 1 \
        PS_USE_PMCPL_IRO_CLK 0 \
    ] \
] [get_bd_cells versal_cips_0]

# --- blink as an IP cell.
create_bd_cell -type ip -vlnv test_vendor:test:blink:0.1 blink_0

# --- Constant 0 driver for blink's async `rst`.
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant xlconstant_0
set_property -dict [list \
    CONFIG.CONST_WIDTH {1} \
    CONFIG.CONST_VAL {0} \
] [get_bd_cells xlconstant_0]

connect_bd_net [get_bd_pins versal_cips_0/pl0_ref_clk] [get_bd_pins blink_0/clk]
connect_bd_net [get_bd_pins xlconstant_0/dout] [get_bd_pins blink_0/rst]

# --- Expose LED.
create_bd_port -dir O led
connect_bd_net [get_bd_ports led] [get_bd_pins blink_0/led]

validate_bd_design
save_bd_design
