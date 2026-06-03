// Write-only BRAM interface
// Provides address, data, byte-write-enable, and enable for write requests.

`timescale 1ns / 1ps

interface bram_write_only_if #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int WE_WIDTH   = DATA_WIDTH / 8
);
  // SPIRIT:ISADDRESS,REQUIRED
  logic [ADDR_WIDTH-1:0] addr;
  // SPIRIT:REQUIRED
  logic                  en;
  // SPIRIT:REQUIRED
  logic [  WE_WIDTH-1:0] we;
  // SPIRIT:ISDATA,REQUIRED
  logic [DATA_WIDTH-1:0] data;

  modport master(output addr, en, we, data);

  modport slave(input addr, en, we, data);

endinterface
