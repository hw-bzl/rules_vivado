// Testbench that uses assertion failure - should be detected as failure
`timescale 1ns / 1ps

module assert_detection_tb;
  logic test_signal;

  initial begin
    $display("Testing assertion failure detection...");
    test_signal = 1'b0;
    #10;
    // This assertion will fail
    assert (test_signal == 1'b1)
    else $error("Assertion failed: test_signal should be 1");
    #10;
    $finish;
  end
endmodule
