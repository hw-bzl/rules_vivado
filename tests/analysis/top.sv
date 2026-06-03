// Minimal design for analysis-only rule coverage. Never synthesized on
// CI — the Vivado-invoking targets are tagged `requires-vivado`.
module top (
    input  logic clk,
    input  logic rst_n,
    output logic q
);
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            q <= 1'b0;
        end else begin
            q <= ~q;
        end
    end
endmodule
