// Simulation top for the `vivado_xsim_test` / `vivado_export_simulation`
// instances. Analysis-only; never run on CI.
module tb;
    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic q;

    top dut (
        .clk(clk),
        .rst_n(rst_n),
        .q(q)
    );

    always #5 clk = ~clk;

    initial begin
        #20 rst_n = 1'b1;
        #100 $finish;
    end
endmodule
