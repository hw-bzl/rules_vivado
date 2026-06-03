module johnson_counter_top (
    input  logic       clk,
    input  logic       reset,
    input  logic       direction,
    output logic [7:0] led
);

  johnson_counter #(
      .COUNTER_BITS(26)
  ) johnson_counter (
      .clk(clk),
      .rst(reset),
      .direction(direction),
      .shift_reg(led)
  );

endmodule
