// Verilog leaf module. Emits a one-cycle pulse whenever `enable`
// rises. Instantiated from `pulse_wrapper.vhd` below via a VHDL
// component declaration bound through `verilog_deps` on the
// vhdl_library target.
module pulse(
    input  logic clk,
    input  logic rst_n,
    input  logic enable,
    output logic tick
);
    logic prev;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prev <= 1'b0;
            tick <= 1'b0;
        end else begin
            prev <= enable;
            tick <= enable & ~prev;
        end
    end
endmodule
