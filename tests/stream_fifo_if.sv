// Stream FIFO Interface Definition
// A simple streaming interface for FIFO-based data transfer

`timescale 1ns / 1ps

interface stream_fifo_if #(
    parameter int ADDR_WIDTH = 16,
    parameter int DATA_WIDTH = 64
);
  // Write channel signals
  // SPIRIT qualifiers: ISADDRESS, ISDATA, ISCLOCK, ISRESET, OPTIONAL, REQUIRED
  // SPIRIT:ISADDRESS,REQUIRED
  logic [ADDR_WIDTH-1:0] wr_addr;
  // SPIRIT:ISDATA,REQUIRED
  logic [DATA_WIDTH-1:0] wr_data;
  // SPIRIT:REQUIRED
  logic                  wr_valid;
  // SPIRIT:REQUIRED
  logic                  wr_ready;
  // SPIRIT:REQUIRED
  logic [           3:0] wr_strobe;

  // Read channel signals
  // SPIRIT:ISADDRESS,REQUIRED
  logic [ADDR_WIDTH-1:0] rd_addr;
  // SPIRIT:ISDATA,REQUIRED
  logic [DATA_WIDTH-1:0] rd_data;
  // SPIRIT:REQUIRED
  logic                  rd_valid;
  // SPIRIT:REQUIRED
  logic                  rd_ready;

  // Status signals
  // SPIRIT:OPTIONAL
  logic                  overflow;
  // SPIRIT:OPTIONAL
  logic                  underflow;
  // SPIRIT:OPTIONAL
  logic [          15:0] fill_level;

  modport master(
      output wr_addr, wr_data, wr_valid, wr_strobe, rd_ready,
      input wr_ready, rd_addr, rd_data, rd_valid, overflow, underflow, fill_level
  );

  modport slave(
      input wr_addr, wr_data, wr_valid, wr_strobe, rd_ready,
      output wr_ready, rd_addr, rd_data, rd_valid, overflow, underflow, fill_level
  );

  modport monitor(
      input wr_addr, wr_data, wr_valid, wr_strobe, rd_ready,
      input wr_ready, rd_addr, rd_data, rd_valid, overflow, underflow, fill_level
  );

endinterface
