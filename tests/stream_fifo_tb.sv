// Stream FIFO Testbench
// Tests the stream_fifo module with the stream_fifo_if interface

`timescale 1ns / 1ps

module stream_fifo_tb;

  parameter int ADDR_WIDTH = 16;
  parameter int DATA_WIDTH = 64;
  parameter int FIFO_DEPTH = 8;

  logic                  clk;
  logic                  rst_n;

  // Interface signals
  logic [ADDR_WIDTH-1:0] wr_addr;
  logic [DATA_WIDTH-1:0] wr_data;
  logic                  wr_valid;
  logic                  wr_ready;
  logic [           3:0] wr_strobe;

  logic [ADDR_WIDTH-1:0] rd_addr;
  logic [DATA_WIDTH-1:0] rd_data;
  logic                  rd_valid;
  logic                  rd_ready;

  logic                  overflow;
  logic                  underflow;
  logic [          15:0] fill_level;

  // DUT
  stream_fifo #(
      .ADDR_WIDTH(ADDR_WIDTH),
      .DATA_WIDTH(DATA_WIDTH),
      .FIFO_DEPTH(FIFO_DEPTH)
  ) dut (
      .clk(clk),
      .rst_n(rst_n),
      .wr_addr(wr_addr),
      .wr_data(wr_data),
      .wr_valid(wr_valid),
      .wr_ready(wr_ready),
      .wr_strobe(wr_strobe),
      .rd_addr(rd_addr),
      .rd_data(rd_data),
      .rd_valid(rd_valid),
      .rd_ready(rd_ready),
      .overflow(overflow),
      .underflow(underflow),
      .fill_level(fill_level)
  );

  // Clock generation
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  // Expected data for verification
  logic [DATA_WIDTH-1:0] expected_data;
  logic [ADDR_WIDTH-1:0] expected_addr;
  int read_count;
  int error_count;

  // Test sequence
  initial begin
    error_count = 0;

    // Initialize
    rst_n = 0;
    wr_addr = '0;
    wr_data = '0;
    wr_valid = 0;
    wr_strobe = 4'hF;
    rd_ready = 0;

    // Reset
    repeat (5) @(posedge clk);
    rst_n = 1;
    repeat (2) @(posedge clk);

    // Write all data first
    $display("Writing %0d items to FIFO...", FIFO_DEPTH);
    for (int i = 0; i < FIFO_DEPTH; i++) begin
      // Wait for FIFO to be ready
      while (!wr_ready) @(posedge clk);
      // Set up data and valid
      wr_addr  = i;
      wr_data  = (i + 1) * 100;
      wr_valid = 1;
      // Clock edge performs the write
      @(posedge clk);
    end
    wr_valid = 0;
    @(posedge clk);
    $display("Write complete. Fill level: %0d", fill_level);

    // Verify fill level
    if (fill_level != FIFO_DEPTH) begin
      $error("Fill level mismatch: expected %0d, got %0d", FIFO_DEPTH, fill_level);
      error_count++;
    end else begin
      $display("Fill level correct: %0d", fill_level);
    end

    // Read all data back
    $display("Reading %0d items from FIFO...", FIFO_DEPTH);
    read_count = 0;

    for (int i = 0; i < FIFO_DEPTH; i++) begin
      // Wait for data to be valid
      rd_ready = 0;
      @(posedge clk);
      while (!rd_valid) @(posedge clk);

      // Check data (rd_ready is 0, so rd_ptr hasn't advanced yet)
      expected_data = (i + 1) * 100;
      expected_addr = i;

      if (rd_data !== expected_data) begin
        $error("Data mismatch at %0d: expected %0d, got %0d", i, expected_data, rd_data);
        error_count++;
      end
      if (rd_addr !== expected_addr) begin
        $error("Addr mismatch at %0d: expected %0d, got %0d", i, expected_addr, rd_addr);
        error_count++;
      end

      // Now consume the data
      rd_ready = 1;
      @(posedge clk);
      read_count++;
    end
    rd_ready = 0;
    @(posedge clk);
    $display("Read complete. Fill level: %0d", fill_level);

    // Verify empty
    if (fill_level != 0) begin
      $error("FIFO not empty: fill_level = %0d", fill_level);
      error_count++;
    end

    // Summary
    @(posedge clk);
    if (error_count == 0) begin
      $display("All tests passed!");
    end else begin
      $display("Tests completed with %0d errors", error_count);
    end
    $finish;
  end

  // Timeout
  initial begin
    #10000;
    $error("Test timeout!");
    $finish;
  end

endmodule
