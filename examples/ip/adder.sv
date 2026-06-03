// A trivial adder wrapped as a Vivado IP. The `vivado_ip_core` rule
// packages this into a repo tree that downstream projects consume via
// their `ip_blocks` attr — the module boundary here becomes the IP's
// port interface after `create_ip`.
module adder #(
    parameter int WIDTH = 8
) (
    input  logic [WIDTH-1:0] a,
    input  logic [WIDTH-1:0] b,
    output logic [WIDTH:0]   sum
);
    assign sum = a + b;
endmodule
