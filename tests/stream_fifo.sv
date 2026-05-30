// Stream FIFO Module
// A simple FIFO implementation using the stream_fifo_if interface

`timescale 1ns / 1ps

module stream_fifo #(
    parameter int ADDR_WIDTH = 16,
    parameter int DATA_WIDTH = 64,
    parameter int FIFO_DEPTH = 16
) (
    input logic clk,
    input logic rst_n,

    // Write interface (master perspective - we are the slave)
    input  logic [ADDR_WIDTH-1:0] wr_addr,
    input  logic [DATA_WIDTH-1:0] wr_data,
    input  logic                  wr_valid,
    output logic                  wr_ready,
    input  logic [           3:0] wr_strobe,

    // Read interface
    output logic [ADDR_WIDTH-1:0] rd_addr,
    output logic [DATA_WIDTH-1:0] rd_data,
    output logic                  rd_valid,
    input  logic                  rd_ready,

    // Status
    output logic        overflow,
    output logic        underflow,
    output logic [15:0] fill_level
);

  // Internal storage
  logic [      DATA_WIDTH-1:0] mem     [FIFO_DEPTH];
  logic [      ADDR_WIDTH-1:0] addr_mem[FIFO_DEPTH];

  // Pointers
  logic [$clog2(FIFO_DEPTH):0] wr_ptr;
  logic [$clog2(FIFO_DEPTH):0] rd_ptr;

  // Status
  logic                        full;
  logic                        empty;

  assign full = (wr_ptr[$clog2(
      FIFO_DEPTH
  )] != rd_ptr[$clog2(
      FIFO_DEPTH
  )]) && (wr_ptr[$clog2(
      FIFO_DEPTH
  )-1:0] == rd_ptr[$clog2(
      FIFO_DEPTH
  )-1:0]);
  assign empty = (wr_ptr == rd_ptr);

  assign wr_ready = !full;
  assign rd_valid = !empty;

  assign fill_level = wr_ptr - rd_ptr;

  // Write logic
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wr_ptr   <= '0;
      overflow <= 1'b0;
    end else begin
      overflow <= 1'b0;
      if (wr_valid && wr_ready) begin
        mem[wr_ptr[$clog2(FIFO_DEPTH)-1:0]] <= wr_data;
        addr_mem[wr_ptr[$clog2(FIFO_DEPTH)-1:0]] <= wr_addr;
        wr_ptr <= wr_ptr + 1;
      end else if (wr_valid && !wr_ready) begin
        overflow <= 1'b1;
      end
    end
  end

  // Read logic
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rd_ptr <= '0;
      underflow <= 1'b0;
    end else begin
      underflow <= 1'b0;
      if (rd_valid && rd_ready) begin
        rd_ptr <= rd_ptr + 1;
      end else if (!rd_valid && rd_ready) begin
        underflow <= 1'b1;
      end
    end
  end

  // Output assignment
  assign rd_data = mem[rd_ptr[$clog2(FIFO_DEPTH)-1:0]];
  assign rd_addr = addr_mem[rd_ptr[$clog2(FIFO_DEPTH)-1:0]];

endmodule
