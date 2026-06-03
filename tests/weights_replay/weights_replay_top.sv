module weights_replay_top #(
    parameter string POLARITY = "ACTIVE_HIGH",
    parameter int    FREQ_HZ  = 125000000
) (
    input  logic       clk,
    input  logic       rst,
    output logic [7:0] led
);

  weights_replay_ip weights_replay_ip_inst (
      .clk(clk),
      .rst(rst),
      .shift_reg(led)
  );

endmodule
