// Testbench that uses $error - should be detected as failure
`timescale 1ns / 1ps

module error_detection_tb;
  initial begin
    $display("Testing $error detection...");
    #10;
    $error("This is a deliberate test error");
    #10;
    $display("Simulation continuing after error");
    $finish;
  end
endmodule
