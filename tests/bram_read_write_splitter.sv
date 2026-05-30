// BRAM Read/Write Splitter
//
// Connects to a single-port BRAM (blk_mem_gen) and exposes separate
// read-only and write-only interfaces. Write has priority when both
// request access on the same cycle.
//
// BRAM Port A signals (from blk_mem_gen IP):
//   addra[31:0]  - address
//   clka         - clock
//   dina[31:0]   - write data
//   douta[31:0]  - read data
//   ena          - enable
//   rsta         - reset
//   wea[3:0]     - byte write enable
//   rsta_busy    - reset busy

`timescale 1ns / 1ps

module bram_read_write_splitter #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int WE_WIDTH   = DATA_WIDTH / 8
) (
    input logic clk,
    input logic rst,

    // Separate read and write interfaces
    bram_read_only_if.slave  rd,
    bram_write_only_if.slave wr,

    // BRAM Port A
    output logic [ADDR_WIDTH-1:0] bram_addr,
    output logic                  bram_clk,
    output logic [DATA_WIDTH-1:0] bram_din,
    input  logic [DATA_WIDTH-1:0] bram_dout,
    output logic                  bram_en,
    output logic                  bram_rst,
    output logic [  WE_WIDTH-1:0] bram_we,
    input  logic                  bram_rsta_busy
);

  logic read_accepted;

  // Clock and reset pass through
  assign bram_clk = clk;
  assign bram_rst = rst;

  // Arbitration: write has priority over read
  always_comb begin
    if (wr.en && !bram_rsta_busy) begin
      // Write operation
      bram_addr     = wr.addr;
      bram_en       = 1'b1;
      bram_we       = wr.we;
      bram_din      = wr.data;
      read_accepted = 1'b0;
    end else if (rd.en && !bram_rsta_busy) begin
      // Read operation
      bram_addr     = rd.addr;
      bram_en       = 1'b1;
      bram_we       = '0;
      bram_din      = '0;
      read_accepted = 1'b1;
    end else begin
      bram_addr     = '0;
      bram_en       = 1'b0;
      bram_we       = '0;
      bram_din      = '0;
      read_accepted = 1'b0;
    end
  end

  // Set valid one cycle after the read is accepted
  always_ff @(posedge clk) begin
    if (rst) begin
      rd.valid <= 1'b0;
    end else begin
      rd.valid <= read_accepted;
    end
  end

  // BRAM douta drives the read data output directly
  assign rd.data = bram_dout;

endmodule
