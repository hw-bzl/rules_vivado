// Minimal SystemVerilog interface — a single-signal ready/valid
// handshake. `vivado_interface_definition` scans the interface for
// modports + signal directions and emits the IP-XACT XML that Vivado
// stores in `<library>/<vendor>/<interface_name>_v<version>/`.
interface stream_if #(
    parameter int WIDTH = 32
) (
    input logic clk,
    input logic rst_n
);
    logic              valid;
    logic              ready;
    logic [WIDTH-1:0]  data;

    modport producer (output valid, input ready, output data);
    modport consumer (input valid, output ready, input data);
endinterface
