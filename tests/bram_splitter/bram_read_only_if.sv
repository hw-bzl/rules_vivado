// Read-only BRAM interface
// Provides address/enable for read requests and returns data with valid strobe.
// Read data is available one cycle after en is asserted.

`timescale 1ns / 1ps

interface bram_read_only_if #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32
);
  // SPIRIT:ISADDRESS,REQUIRED
  logic [ADDR_WIDTH-1:0] addr;
  // SPIRIT:REQUIRED
  logic                  en;
  // SPIRIT:ISDATA,REQUIRED
  logic [DATA_WIDTH-1:0] data;
  // SPIRIT:REQUIRED
  logic                  valid;

  modport master(output addr, en, input data, valid);

  modport slave(input addr, en, output data, valid);

endinterface
