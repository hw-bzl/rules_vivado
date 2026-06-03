// Trivial Versal target: a divide-by-2^24 clock-blinked LED. Kept
// small so the full synth -> route -> device-image pipeline finishes
// quickly under CI. The point of this scenario is exercising the
// `vivado_device_image` (.pdi) code path — the RTL is
// deliberately boring.
module blink (
    input  logic clk,
    input  logic rst,
    output logic led
);
  logic [23:0] counter;
  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      counter <= '0;
      led     <= 1'b0;
    end else begin
      counter <= counter + 24'd1;
      led     <= counter[23];
    end
  end
endmodule
