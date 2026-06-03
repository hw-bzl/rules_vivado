-- VHDL wrapper around the Verilog `pulse` module. The component
-- declaration binds to a black-box symbol; the actual module comes
-- in through `verilog_deps` on the vhdl_library target below. This
-- exercises the cross-language depset walk in `hdl_sources_data`
-- (common.bzl) — synth must see BOTH `pulse.sv` and this wrapper
-- staged into the project, with the correct library/standard
-- annotations per source.

library ieee;
use ieee.std_logic_1164.all;

entity pulse_wrapper is
    port (
        clk    : in  std_logic;
        rst_n  : in  std_logic;
        enable : in  std_logic;
        tick   : out std_logic
    );
end pulse_wrapper;

architecture behavioral of pulse_wrapper is
    component pulse
        port (
            clk    : in  std_logic;
            rst_n  : in  std_logic;
            enable : in  std_logic;
            tick   : out std_logic
        );
    end component;
begin
    u_pulse : pulse
        port map (
            clk    => clk,
            rst_n  => rst_n,
            enable => enable,
            tick   => tick
        );
end behavioral;
