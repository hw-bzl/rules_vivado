// Trivial top-level module: a 1-bit blinking LED.
module hello (
    input  wire clk,
    input  wire rst,
    output reg  led
);
  always_ff @(posedge clk) begin
    if (rst) led <= 1'b0;
    else     led <= ~led;
  end
endmodule
