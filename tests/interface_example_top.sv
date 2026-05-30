module interface_example_top (
    input logic clk,
    input logic rst
);

  interface_example interface_example (
      .clk(clk),
      .rst(rst)
  );

endmodule
