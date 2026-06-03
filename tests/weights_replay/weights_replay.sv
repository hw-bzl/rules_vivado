
module weights_replay #(
    parameter int COUNTER_BITS = 3
) (
    input logic clk,
    input logic rst,
    output logic [7:0] shift_reg
);

  logic [COUNTER_BITS - 1:0] counter;
  logic [2:0] weights_address;
  logic [7:0] weights[1][8];

// Workspace-relative path — the xsim_test wrapper symlinks the
// runfiles workspace tree into `WORK_DIR`, so xsim's CWD sees the
// same layout the source tree has. The path points at the packaged
// IP's `src/` dir (`vivado_ip_core` stages `.mem` data files
// there) rather than the source location `//tests/johnson_counter:
// test.mem`, because Vivado's `export_simulation -export_source_files`
// only preserves HDL sources — data files ride along inside the IP
// tree that gets staged into runfiles.
initial begin
    $readmemh("tests/weights_replay/weights_replay_ip/src/test.mem", weights);
end

  always @(posedge clk) begin
    if (rst) begin
      weights_address <= 0;
      counter <= 0;
    end else begin
      // When the top bit flips, shift the registers.
      if (counter == (1 << COUNTER_BITS) - 1) begin
        counter <= 0;
        weights_address <= weights_address + 1;
      end else begin
        counter <= counter + 1;
      end
    end
    shift_reg <= weights[0][weights_address];
  end

endmodule
