// Trivial testbench that finishes after one delta cycle — enough for
// xsim / vivado_export_simulation to elaborate and exit. The point is
// the hook wiring around it.
module tb;
    initial begin
        $display("hooks demo: xsim tb reached $finish");
        $finish;
    end
endmodule
