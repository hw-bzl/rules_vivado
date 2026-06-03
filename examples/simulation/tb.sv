// Trivial testbench that finishes after one delta cycle. Just enough
// for xsim to elaborate, run, and exit cleanly — the point of this
// example is the Bazel wiring around xsim, not the testbench content.
module tb;
    initial begin
        $display("hello from xsim_test");
        $finish;
    end
endmodule
